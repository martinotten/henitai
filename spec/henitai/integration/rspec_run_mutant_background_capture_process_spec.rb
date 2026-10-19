# frozen_string_literal: true

require "fileutils"
require "open3"
require "spec_helper"
require "timeout"
require "tmpdir"

RSpec.describe Henitai::Integration::Rspec, "#run_mutant" do
  def with_temp_workspace
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { yield dir }
    end
  end

  def write_file(dir, relative_path, source)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  def repo_gemfile
    File.expand_path("../../../Gemfile", __dir__)
  end

  def background_sample_source
    <<~RUBY
      class BackgroundCaptureSample
        def self.value(a, b)
          a + b
        end
      end
    RUBY
  end

  # The example leaves a sleep running that inherits the mutant child's
  # stdout/stderr pipes. The pid is recorded so the spec can verify cleanup.
  def background_spec_source(pid_path)
    <<~RUBY
      require_relative "../lib/background_capture_sample"

      RSpec.describe BackgroundCaptureSample do
        it "passes while a grandchild keeps the output pipe open" do
          pid = Process.detach(spawn("sleep", "20")).pid
          File.write(#{pid_path.dump}, pid.to_s)
          expect(described_class.value(3, 1)).to be_a(Integer)
        end
      end
    RUBY
  end

  def child_script(source_path, spec_path)
    <<~RUBY
      require "henitai"

      source_path = #{source_path.dump}
      spec_path = #{spec_path.dump}
      require source_path
      subject = Henitai::SubjectResolver.new.resolve_from_files([source_path]).find do |candidate|
        candidate.expression == "BackgroundCaptureSample.value"
      end
      mutant = Henitai::MutantGenerator.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new]
      ).first
      result = Henitai::Integration::Rspec.new.run_mutant(
        mutant: mutant,
        test_files: [spec_path],
        timeout: 10.0
      )

      abort("unexpected=\#{result.status}\\n\#{result.combined_output}") unless result.status == :survived
      puts result.status
    RUBY
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def kill_background_process(pid_path)
    return unless File.exist?(pid_path)

    pid = File.read(pid_path).to_i
    Process.kill("KILL", pid) if process_alive?(pid)
  rescue Errno::ESRCH
    nil
  end

  def run_background_capture(dir, pid_path, source_path, spec_path)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    stdout, stderr, status = Timeout.timeout(60) do
      Open3.capture3(
        { "BUNDLE_GEMFILE" => repo_gemfile },
        "bundle", "exec", "ruby", "-e", child_script(source_path, spec_path),
        chdir: dir
      )
    end
    {
      survived: status.success? && stdout.include?("survived"),
      fast: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started < 9.0,
      background_pid_dead: !process_alive?(File.read(pid_path).to_i),
      output: [stdout, stderr].join("\n")
    }
  end

  it "does not classify a passing mutant as timed out when a grandchild holds the output pipe" do
    with_temp_workspace do |dir|
      source_path = write_file(dir, "lib/background_capture_sample.rb", background_sample_source)
      pid_path = File.join(dir, "background.pid")
      spec_path = write_file(dir, "spec/background_capture_sample_spec.rb", background_spec_source(pid_path))

      begin
        outcome = run_background_capture(dir, pid_path, source_path, spec_path)

        expect(outcome.except(:output)).to eq(survived: true, fast: true, background_pid_dead: true),
                                           outcome[:output]
      ensure
        kill_background_process(pid_path)
      end
    end
  end
end
