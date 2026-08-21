# frozen_string_literal: true

require "fileutils"
require "minitest"
require "open3"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Integration::Minitest do
  before do
    allow(Process).to receive(:setpgid).and_return(0)
    allow(Process).to receive(:kill).and_raise(Errno::ESRCH)
    # These specs execute the fork block in-process (see stub_process_fork),
    # so the child bootstrap runs here rather than in a real child. The
    # watchdog must be stubbed: given this process as its parent_pid it would
    # see ppid != parent_pid, conclude it had been orphaned, and call exit!(2),
    # killing the RSpec run with no output at all.
    allow(Henitai::OrphanWatchdog).to receive(:start)
  end

  def with_temp_workspace
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { yield dir }
    end
  end

  def with_env(key, value)
    original = ENV.fetch(key, nil)

    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end

    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end

  def write_file(dir, relative_path, source)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  def sample_source
    <<~RUBY
      class Sample
        def value
        end
      end
    RUBY
  end

  def minitest_source
    <<~RUBY
      require "minitest/autorun"
      require_relative "../lib/sample"

      class SampleTest < Minitest::Test
        def test_value
        end
      end
    RUBY
  end

  def require_source
    <<~RUBY
      require "minitest/autorun"
      require "lib/sample"

      class SampleTest < Minitest::Test
        def test_value
        end
      end
    RUBY
  end

  def write_sample_library(dir)
    write_file(dir, "lib/sample.rb", sample_source)
  end

  def stub_minitest_run(order, return_value: true)
    allow(Minitest).to receive(:run) do |argv|
      order << [:minitest, argv]
      return_value
    end
  end

  def stub_minitest_process_flow(order, test_file, minitest_result: true)
    stub_minitest_exit(order)
    stub_minitest_fork(order)
    stub_minitest_wait(order)
    stub_minitest_status
    stub_minitest_requires(order)
    stub_minitest_run(order, return_value: minitest_result)
    write_sample_library(File.dirname(test_file, 2))
  end

  def stub_minitest_exit(order)
    allow(Process).to receive(:exit) { |status| order << [:exit, status] }
  end

  def stub_minitest_fork(order)
    allow(Process).to receive(:fork) do |&block|
      order << :fork
      # The inline "child" mutates ENV (e.g. HENITAI_MUTANT_ID); a real fork
      # would isolate that, so restore the parent environment afterwards.
      parent_env = ENV.to_h
      begin
        block.call
      ensure
        ENV.replace(parent_env)
      end
      12_345
    end
  end

  def stub_minitest_wait(order)
    allow(Process).to receive(:wait) do |pid, flags = nil|
      order << [:wait, pid, flags]
      pid
    end
  end

  def stub_minitest_status
    allow(Process).to receive(:last_status).and_return(
      Struct.new(:success?).new(true)
    )
  end

  def stub_minitest_requires(order)
    allow(Henitai::Mutant::Activator).to receive(:activate!) do |_mutant|
      order << :activate
    end
    allow(Kernel).to receive(:require).and_return(true)
  end

  def build_log_paths(name)
    {
      stdout_path: "reports/mutation-logs/#{name}.stdout.log",
      stderr_path: "reports/mutation-logs/#{name}.stderr.log",
      log_path: "reports/mutation-logs/#{name}.log"
    }
  end

  it "selects minitest files by subject prefix" do
    with_temp_workspace do |dir|
      write_file(dir, "test/sample_test.rb", minitest_source)
      write_file(dir, "test/other_test.rb", minitest_source.sub("Sample", "Other"))

      subject = Henitai::Subject.parse("Sample#value")

      expect(described_class.new.select_tests(subject)).to eq(["test/sample_test.rb"])
    end
  end

  it "falls back to tests that require the source file" do
    with_temp_workspace do |dir|
      source_file = write_sample_library(dir)
      write_file(dir, "test/widget_test.rb", require_source)

      subject = Henitai::Subject.new(
        namespace: "Widget",
        method_name: "value",
        source_location: {
          file: source_file,
          range: nil
        }
      )

      expect(described_class.new.select_tests(subject)).to eq(["test/widget_test.rb"])
    end
  end

  it "advertises per-test coverage support" do
    expect(described_class.new.per_test_coverage_supported?).to be(true)
  end

  it "uses the baseline log name and wait timeout when running the suite" do
    integration = described_class.new

    with_temp_workspace do
      calls = []
      log_paths = {
        stdout_path: "reports/mutation-logs/baseline.stdout.log",
        stderr_path: "reports/mutation-logs/baseline.stderr.log",
        log_path: "reports/mutation-logs/baseline.log"
      }

      allow(integration).to receive(:scenario_log_paths) do |name|
        calls << [:scenario_log_paths, name]
        log_paths
      end
      allow(Process).to receive(:spawn).and_return(4321)
      allow(integration).to receive(:wait_with_timeout) do |pid, timeout|
        calls << [:wait_with_timeout, pid, timeout]
        :timeout
      end
      allow(integration).to receive(:build_result).and_return(:timeout)

      integration.run_suite(["test/sample_test.rb"], timeout: 4.0)

      expect(calls).to eq([
                            [:scenario_log_paths, "baseline"],
                            [:wait_with_timeout, 4321, 4.0]
                          ])
    end
  end

  it "cleans up and reaps the baseline child when the wait result is nil" do
    integration = described_class.new

    with_temp_workspace do
      calls = []

      allow(Process).to receive(:spawn).and_return(4321)
      allow(integration).to receive_messages(wait_with_timeout: nil, build_result: :survived)
      allow(integration).to receive(:cleanup_child_process) do |pid|
        calls << [:cleanup, pid]
      end
      allow(integration).to receive(:reap_child) do |pid|
        calls << [:reap, pid]
      end

      result = integration.run_suite(["test/sample_test.rb"], timeout: 4.0)

      expect([result, calls]).to eq([
                                      :survived,
                                      [[:cleanup, 4321], [:reap, 4321]]
                                    ])
    end
  end

  it "does not reap the baseline child when the wait result is present" do
    integration = described_class.new

    with_temp_workspace do
      calls = []

      allow(Process).to receive(:spawn).and_return(4321)
      allow(integration).to receive_messages(
        wait_with_timeout: Struct.new(:success?).new(true),
        build_result: :killed
      )
      allow(integration).to receive(:cleanup_child_process) do |pid|
        calls << [:cleanup, pid]
      end
      allow(integration).to receive(:reap_child) do |pid|
        calls << [:reap, pid]
      end

      integration.run_suite(["test/sample_test.rb"], timeout: 4.0)

      expect(calls).to eq([[:cleanup, 4321]])
    end
  end

  it "skips cleanup entirely when the baseline process never spawned" do
    integration = described_class.new

    with_temp_workspace do
      calls = []

      allow(Process).to receive(:spawn).and_return(nil)
      allow(integration).to receive_messages(wait_with_timeout: :timeout, build_result: :timeout)
      allow(integration).to receive(:cleanup_child_process) { |pid| calls << [:cleanup, pid] }
      allow(integration).to receive(:reap_child) { |pid| calls << [:reap, pid] }

      integration.run_suite(["test/sample_test.rb"], timeout: 4.0)

      expect(calls).to be_empty
    end
  end

  it "spawns the suite process with the expected env, command, and streams" do
    integration = described_class.new
    spawn_calls = []

    with_env("RAILS_ENV", nil) do
      with_temp_workspace do
        allow(Process).to receive(:spawn) do |*args, out:, err:|
          spawn_calls << args
          out.write("out-line\n")
          err.write("err-line\n")
          4321
        end
        allow(integration).to receive(:wait_with_timeout).and_return(Struct.new(:success?).new(true))

        result = integration.run_suite(["test/sample_test.rb"], timeout: 4.0)
        env, *command = spawn_calls.fetch(0)

        expect([result.stdout, result.stderr, env, command]).to eq(
          [
            "out-line\n", "err-line\n",
            { "PARALLEL_WORKERS" => "1", "RAILS_ENV" => "test" },
            integration.suite_command(["test/sample_test.rb"])
          ]
        )
      end
    end
  end

  def build_mutant_log_support_double(log_paths, mutant)
    log_support = instance_double(Henitai::Integration::ScenarioLogSupport)
    allow(log_support).to receive_messages(read_log_file: "", write_combined_log: nil)
    allow(log_support).to receive(:with_coverage_dir).with(mutant.id).and_yield
    allow(log_support).to receive(:capture_child_output).with(log_paths).and_yield
    log_support
  end

  def stub_mutant_log_support(integration, mutant, order)
    log_support = build_mutant_log_support_double(build_log_paths("mutant-setup"), mutant)
    allow(Henitai::Integration::MinitestLoadPath).to receive(:ensure!) do
      order << :setup_load_path
    end
    allow(integration).to receive(:scenario_log_support).and_return(log_support)
  end

  def run_mutant_with_stubbed_flow(order, minitest_result:)
    with_temp_workspace do |dir|
      test_file = write_file(dir, "test/sample_test.rb", minitest_source)
      mutant = Struct.new(:id).new("setup")
      integration = described_class.new
      stub_mutant_log_support(integration, mutant, order)
      stub_minitest_process_flow(order, test_file, minitest_result:)

      integration.run_mutant(mutant:, test_files: [test_file], timeout: 4.0)
    end
  end

  it "sets up the load path before running a mutant" do
    order = []

    run_mutant_with_stubbed_flow(order, minitest_result: true)

    expect(order.first).to eq(:setup_load_path)
  end

  context "when Minitest.run passes" do
    it "exits the child process with status 0" do
      order = []

      run_mutant_with_stubbed_flow(order, minitest_result: true)

      expect(order).to include([:exit, 0])
    end
  end

  context "when Minitest.run fails" do
    it "exits the child process with status 1" do
      order = []

      run_mutant_with_stubbed_flow(order, minitest_result: false)

      expect(order).to include([:exit, 1])
    end
  end

  it "delegates suite_command to MinitestSuiteCommand" do
    integration = described_class.new
    test_files = ["test/sample_test.rb"]

    expect(integration.suite_command(test_files)).to eq(
      Henitai::Integration::MinitestSuiteCommand.new.build(test_files)
    )
  end

  it "lists minitest test files and excludes system tests" do
    with_temp_workspace do |dir|
      write_file(dir, "test/models/sample_test.rb", "")
      write_file(dir, "test/models/sample_spec.rb", "")
      write_file(dir, "test/system/browser_test.rb", "")

      expect(described_class.new.test_files).to contain_exactly("test/models/sample_test.rb",
                                                                "test/models/sample_spec.rb")
    end
  end

  it "is a sibling of the rspec adapter, not a subtype" do
    inherits_base = described_class.ancestors.include?(Henitai::Integration::Base)
    inherits_rspec = described_class.ancestors.include?(Henitai::Integration::Rspec)

    expect([inherits_base, inherits_rspec]).to eq([true, false])
  end

  it "does not expose rspec-only runner methods" do
    integration = described_class.new
    rspec_only = %i[
      run_rspec_runner build_rspec_runner configure_rspec_runner
      load_rspec_spec_files run_rspec_specs rspec_suite_runner_script
    ]

    exposed = rspec_only.select { |name| integration.respond_to?(name, true) }

    expect(exposed).to eq([])
  end

  it "builds a scenario result from the captured child logs" do
    with_temp_workspace do
      log_paths = build_log_paths("mutant-build")
      FileUtils.mkdir_p(File.dirname(log_paths[:stdout_path]))
      File.write(log_paths[:stdout_path], "out\n")
      File.write(log_paths[:stderr_path], "err\n")
      wait_result = Struct.new(:success?, :exitstatus).new(true, 0)

      result = described_class.new.build_result(wait_result, log_paths)

      expect([result.status, result.stdout, result.stderr, File.read(log_paths[:log_path])]).to eq(
        [:survived, "out\n", "err\n", "stdout:\nout\n\nstderr:\nerr\n"]
      )
    end
  end

  it "names mutant logs and scenario log paths the same way as rspec" do
    integration = described_class.new
    mutant = Struct.new(:id).new("abc")

    with_env("HENITAI_REPORTS_DIR", "reports") do
      expect(integration.scenario_log_paths(integration.mutant_log_name(mutant))).to eq(
        stdout_path: "reports/mutation-logs/mutant-abc.stdout.log",
        stderr_path: "reports/mutation-logs/mutant-abc.stderr.log",
        log_path: "reports/mutation-logs/mutant-abc.log"
      )
    end
  end
end
