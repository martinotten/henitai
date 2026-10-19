# frozen_string_literal: true

require "fileutils"
require "open3"
require "spec_helper"
require "tmpdir"

# Equivalence of the fork-server execution model (ADR-15) with per-mutant
# boot, for RSpec and Minitest on the linear and the parallel path: the same
# mutants of a small project get the same statuses, the environment boots once,
# a runaway mutant is reported as a timeout, and no process outlives its run.
# rubocop:disable Metrics/MethodLength,Metrics/AbcSize
RSpec.describe Henitai::ForkServer do
  def write_file(dir, relative_path, source)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
  end

  def write_sources(dir)
    write_file(dir, "lib/fs_calc.rb", <<~RUBY)
      class FsCalc
        def self.add(a, b)
          a + b
        end

        def self.unchecked(a, b)
          a * b
        end
      end
    RUBY
    write_file(dir, "lib/fs_loop.rb", <<~RUBY)
      class FsLoop
        def self.count
          i = 0
          i = i + 1 while i < 3
          i
        end
      end
    RUBY
    write_file(dir, "lib/fs_other.rb", <<~RUBY)
      class FsOther
        def self.value
          1 + 1
        end
      end
    RUBY
  end

  def recorder_source
    <<~RUBY
      module FsLog
        def self.boot
          File.open(File.join(ENV.fetch("FS_BOOT_LOG"), "boots"), "a") { |file| file.puts(Process.pid) }
        end

        def self.ran(name)
          line = [Process.pid, name, ENV.fetch("HENITAI_WORKER_SLOT", "-")].join("|")
          File.open(File.join(ENV.fetch("FS_BOOT_LOG"), "runs"), "a") { |file| file.puts(line) }
        end

        def self.leave_sleeper
          sleeper = Process.spawn("sleep", "60")
          File.write(File.join(ENV.fetch("FS_BOOT_LOG"), "\#{Process.pid}.pids"), "\#{Process.pid} \#{sleeper}")
        end
      end
      FsLog.boot
    RUBY
  end

  def write_rspec_specs(dir)
    write_file(dir, ".rspec", "--require spec_helper\n")
    write_file(dir, "spec/spec_helper.rb", recorder_source)
    write_file(dir, "spec/fs_calc_spec.rb", <<~RUBY)
      require_relative "../lib/fs_calc"

      RSpec.describe FsCalc do
        it("adds") { FsLog.ran("adds"); expect(described_class.add(2, 3)).to eq(5) }
        it("multiplies without asserting") { FsLog.ran("multiplies"); described_class.unchecked(2, 3) }
      end
    RUBY
    write_file(dir, "spec/fs_loop_spec.rb", <<~RUBY)
      require_relative "../lib/fs_loop"

      RSpec.describe FsLoop do
        it "counts" do
          FsLog.ran("counts")
          FsLog.leave_sleeper
          expect(described_class.count).to eq(3)
        end
      end
    RUBY
    write_file(dir, "spec/fs_other_spec.rb", <<~RUBY)
      require_relative "../lib/fs_other"

      RSpec.describe FsOther do
        it("is two") { FsLog.ran("is_two"); expect(described_class.value).to eq(2) }
      end
    RUBY
  end

  def write_minitest_tests(dir)
    write_file(dir, "test/test_helper.rb", "require \"minitest/autorun\"\n#{recorder_source}")
    write_file(dir, "test/fs_calc_test.rb", <<~RUBY)
      require_relative "test_helper"
      require_relative "../lib/fs_calc"

      class FsCalcTest < Minitest::Test
        def test_adds = (FsLog.ran("adds"); assert_equal(5, FsCalc.add(2, 3)))
        def test_multiplies_without_asserting = (FsLog.ran("multiplies"); FsCalc.unchecked(2, 3))
      end
    RUBY
    write_file(dir, "test/fs_loop_test.rb", <<~RUBY)
      require_relative "test_helper"
      require_relative "../lib/fs_loop"

      class FsLoopTest < Minitest::Test
        def test_counts
          FsLog.ran("counts")
          FsLog.leave_sleeper
          assert_equal(3, FsLoop.count)
        end
      end
    RUBY
    write_file(dir, "test/fs_other_test.rb", <<~RUBY)
      require_relative "test_helper"
      require_relative "../lib/fs_other"

      class FsOtherTest < Minitest::Test
        def test_is_two = (FsLog.ran("is_two"); assert_equal(2, FsOther.value))
      end
    RUBY
  end

  def write_tests(dir, integration)
    integration == "rspec" ? write_rspec_specs(dir) : write_minitest_tests(dir)
  end

  def config_source(integration, jobs, fork_server, reports_dir)
    <<~YAML
      integration:
        name: #{integration}
      jobs: #{jobs}
      reports_dir: #{reports_dir}
      mutation:
        operators: light
        timeout: 2
        control_runs: false
        fork_server: #{fork_server}
    YAML
  end

  def pipeline_script
    <<~RUBY
      require "henitai"

      config = Henitai::Configuration.new(path: ENV.fetch("FS_CONFIG"))
      files = Dir["lib/*.rb"].map { |file| File.expand_path(file) }
      subjects = Henitai::SubjectResolver.new.resolve_from_files(files)
      mutants = Henitai::MutantGenerator.new.generate(
        subjects,
        [Henitai::Operators::ArithmeticOperator.new, Henitai::Operators::EqualityOperator.new]
      )
      results = Henitai::ExecutionEngine.new.run(mutants, Henitai::Integration.for(ENV.fetch("FS_INTEGRATION")).new, config)
      lines = results.map { |m| "STATUS=\#{m.subject.expression}|\#{m.description}|\#{m.status}" }
      puts lines.sort
    RUBY
  end

  def run_pipeline(dir, integration, jobs, fork_server)
    tag = "#{fork_server}-#{jobs}"
    reports_dir = File.join(dir, "reports-#{tag}")
    boot_log = File.join(dir, "boot-#{tag}")
    FileUtils.mkdir_p(boot_log)
    config = File.join(dir, ".henitai-#{tag}.yml")
    File.write(config, config_source(integration, jobs, fork_server, reports_dir))
    env = { "BUNDLE_GEMFILE" => File.expand_path("../../Gemfile", __dir__), "FS_CONFIG" => config,
            "FS_BOOT_LOG" => boot_log, "HENITAI_REPORTS_DIR" => reports_dir, "FS_INTEGRATION" => integration }
    stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", "-e", pipeline_script, chdir: dir)
    { statuses: stdout.lines.grep(/\ASTATUS=/).map(&:chomp), stderr:, status:, boot_log:, reports_dir: }
  end

  def boot_pids(run)
    File.readlines(File.join(run[:boot_log], "boots"), chomp: true)
  end

  def test_runs(run)
    File.readlines(File.join(run[:boot_log], "runs"), chomp: true).map { |line| line.split("|") }
  end

  def recorded_pids(run)
    Dir[File.join(run[:boot_log], "*.pids")].flat_map { |path| File.read(path).split.map(&:to_i) }
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def wait_until_gone(pids)
    deadline = Time.now + 5
    sleep(0.1) while pids.any? { |pid| alive?(pid) } && Time.now < deadline
    pids.select { |pid| alive?(pid) }
  end

  def expect_same_statuses(plain, forked)
    expect([plain[:status].success?, forked[:status].success?]).to eq([true, true]), forked[:stderr]
    expect(forked[:statuses]).to eq(plain[:statuses]), forked[:stderr]
    expect(forked[:statuses].map { |line| line[/[a-z_]+\z/] }.uniq).to include("killed", "survived", "timeout")
    expect(forked[:stderr]).not_to match(/falling back|jobs > 1/)
  end

  def expect_one_boot_and_clean_runs(plain, forked, jobs)
    server_pid = boot_pids(forked).first
    runs = test_runs(forked)
    expect([boot_pids(forked).size, boot_pids(plain).size > 1]).to eq([1, true])
    expect(runs.map(&:first)).not_to include(server_pid)
    expect(runs.uniq.size).to eq(runs.size)
    expect(runs.map(&:last).uniq - (0...jobs).map(&:to_s).push("-")).to eq([])
    expect(runs.map(&:last)).not_to include("-") if jobs > 1
  end

  %w[rspec minitest].each do |integration|
    it "behaves like per-mutant boot for #{integration} with jobs 1 and 2", :aggregate_failures do
      Dir.mktmpdir do |dir|
        write_sources(dir)
        write_tests(dir, integration)
        plain = run_pipeline(dir, integration, 1, false)

        [1, 2].each do |jobs|
          forked = run_pipeline(dir, integration, jobs, true)
          expect_same_statuses(plain, forked)
          expect_one_boot_and_clean_runs(plain, forked, jobs)
          expect(forked[:statuses].grep(/FsLoop\.count\|.*\|timeout\z/)).not_to be_empty
          expect(wait_until_gone(recorded_pids(forked))).to eq([])
        end
      end
    end
  end
end
# rubocop:enable Metrics/MethodLength,Metrics/AbcSize
