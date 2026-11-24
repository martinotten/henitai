# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Integration double whose children are SpecSupport::FakeChildren: every
# spawn is recorded, with the environment the child would inherit, and
# #build_result answers the outcomes queued with #answer (default: killed;
# the last outcome repeats).
IntegrationSpy = Class.new do
  attr_reader :calls, :children

  def initialize(children)
    @children = children
    @calls = Hash.new(0)
    @outcomes = []
  end

  def answer(*outcomes)
    @outcomes = outcomes
    self
  end

  def select_tests(subject)
    @calls[:select_tests] += 1
    @calls[:last_subject] = subject.expression
    ["spec/foo_spec.rb"]
  end

  def test_files
    ["spec/foo_spec.rb"]
  end

  def spawn_mutant(mutant:, test_files:)
    @calls[:spawn_mutant] += 1
    @calls[:last_test_files] = test_files
    @calls[:env] = ENV.to_h.slice("HENITAI_REPORTS_DIR", "HENITAI_COVERAGE_DIR")
    children.spawn(mutant, test_files)
  end

  def build_result(_wait_result, _log_paths)
    outcome = @outcomes.size > 1 ? @outcomes.shift : @outcomes.first
    outcome || Henitai::ScenarioExecutionResult.new(status: :killed, stdout: "", stderr: "", log_path: nil)
  end
end

RSpec.describe Henitai::ExecutionEngine do
  let(:children) { Henitai::SpecSupport::FakeChildren.new }

  def build_subject(expression)
    Struct.new(:expression).new(expression)
  end

  def build_mutant(status, expression)
    Struct.new(:status, :subject, :covered_by, :tests_completed) do
      def pending?
        status == :pending
      end
    end.new(status, build_subject(expression))
  end

  def build_integration
    IntegrationSpy.new(children)
  end

  # The real worker runner and scheduler, on fake children.
  def build_engine
    described_class.new(runtime: children, wakeup: Henitai::SpecSupport::FakeWakeup.new)
  end

  def build_config(jobs: 1)
    Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries).new(12.5, "coverage", jobs, 3)
  end

  def outcome(status, killing_tests: [], hanging_test: nil)
    Henitai::ScenarioExecutionResult.new(status:, stdout: "", stderr: "", log_path: nil, killing_tests:,
                                         hanging_test:)
  end

  def stub_worker_runner(control_stats: nil, flaky_retry_count: 0)
    runner = instance_double(Henitai::ProcessWorkerRunner, flaky_retry_count:, run: [], control_stats:)
    allow(Henitai::ProcessWorkerRunner).to receive(:new).and_return(runner)
    runner
  end

  def recorder
    Struct.new(:calls) do
      def progress(mutant, **)
        calls << mutant.status
      end
    end.new([])
  end

  describe "one driver for every jobs value (ADR-20)" do
    {
      nil => 1,
      0 => 1,
      1 => 1,
      3 => 3
    }.each do |jobs, slots|
      it "runs jobs=#{jobs.inspect} through one worker runner with #{slots} slot(s)" do
        stub_worker_runner

        build_engine.run([build_mutant(:pending, "Foo#bar")], build_integration, build_config(jobs:))

        expect(Henitai::ProcessWorkerRunner).to have_received(:new).with(hash_including(worker_count: slots)).once
      end
    end

    [1, 2].each do |jobs|
      it "gives every mutant a verdict with jobs=#{jobs}" do
        mutants = 3.times.map { |index| build_mutant(:pending, "Foo#bar#{index}") }
        integration = build_integration.answer(outcome(:killed), outcome(:survived), outcome(:timeout))

        build_engine.run(mutants, integration, build_config(jobs:))

        expect(mutants.map(&:status)).to eq(%i[killed survived timeout])
      end
    end
  end

  describe "control runs" do
    def config_with_control_runs(enabled)
      Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries, :control_runs)
            .new(12.5, "coverage", 1, 3, enabled)
    end

    it "hands the worker runner a control run for its gate" do
      mutants = [build_mutant(:pending, "Foo#bar")]
      runner = stub_worker_runner(control_stats: { verified: 1, failed: 0, reclassified: 0 })

      build_engine.run(mutants, build_integration, config_with_control_runs(true))

      expect(runner).to have_received(:run)
        .with(mutants, anything, anything, anything, hash_including(control_run: an_instance_of(Henitai::ControlRun)))
    end

    it "hands the worker runner no control run when control runs are disabled" do
      mutants = [build_mutant(:pending, "Foo#bar")]
      runner = stub_worker_runner

      build_engine.run(mutants, build_integration, config_with_control_runs(false))

      expect(runner).to have_received(:run).with(mutants, anything, anything, anything,
                                                 hash_including(control_run: nil))
    end

    it "warns when the control gate reclassified verdicts" do
      stub_worker_runner(control_stats: { verified: 3, failed: 1, reclassified: 4 })

      expect do
        build_engine.run([build_mutant(:pending, "Foo#bar")], build_integration, config_with_control_runs(true))
      end
        .to output(/control runs failed for 1 of 3 subjects; 4 detected verdicts reclassified as CompileError/)
        .to_stderr
    end
  end

  describe "HENITAI_WORKER_SLOT" do
    around do |example|
      original = ENV.fetch("HENITAI_WORKER_SLOT", nil)
      ENV["HENITAI_WORKER_SLOT"] = "sentinel"
      example.run
    ensure
      original.nil? ? ENV.delete("HENITAI_WORKER_SLOT") : ENV["HENITAI_WORKER_SLOT"] = original
    end

    it "exposes slot 0 to every child of a one-slot run" do
      mutants = [build_mutant(:pending, "Foo#bar"), build_mutant(:pending, "Foo#baz")]

      build_engine.run(mutants, build_integration, build_config)

      expect(children.spawns.map { |spawn| spawn[:worker_slot] }).to eq(%w[0 0])
    end

    it "restores the variable after the run" do
      build_engine.run([build_mutant(:pending, "Foo#bar")], build_integration, build_config)

      expect(ENV.fetch("HENITAI_WORKER_SLOT", nil)).to eq("sentinel")
    end
  end

  describe "timeout calibration" do
    def build_calibrating_config(dir, timeout_configured:, multiplier: 3.0)
      config = Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries, :timeout_multiplier) do
        attr_accessor :timeout_configured

        def timeout_configured? = timeout_configured
      end.new(12.5, dir, 1, 3, multiplier)
      config.timeout_configured = timeout_configured
      config
    end

    def write_timing_report(dir, durations)
      payload = durations.transform_values do |duration|
        { "coverage" => {}, "duration" => duration }
      end
      File.write(File.join(dir, "henitai_per_test.json"), JSON.dump(payload))
    end

    def write_boot_report(dir, seconds)
      File.write(File.join(dir, "henitai_suite_boot.json"), JSON.dump("boot_seconds" => seconds))
    end

    # The timeouts the engine's resolver hands the scheduler, one per mutant.
    def resolved_timeouts(config, mutants: [build_mutant(:pending, "Foo#bar")], engine: build_engine,
                          integration: build_integration)
      timeouts = []
      allow(stub_worker_runner).to receive(:run) do |run_mutants, _integration, _config, _progress, options|
        run_mutants.each do |mutant|
          timeouts << options[:timeout_resolver].call(mutant, options[:test_file_resolver].call(mutant))
        end
        []
      end
      engine.run(mutants, integration, config)
      timeouts
    end

    it "includes the measured suite boot time in the calibrated timeout" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        write_timing_report(dir, "spec/foo_spec.rb" => 2.0)
        write_boot_report(dir, 1.0)

        expect(resolved_timeouts(config)).to eq([9.0])
      end
    end

    it "keeps suite boot in the calibrated timeout while the fork server is active" do
      fork_runner = instance_double(Henitai::ForkServer::MutantRunner, stop: nil, active?: true, runtime: nil)
      integration = instance_double(Henitai::Integration::Rspec, fork_server_supported?: true)
      allow(Henitai::ForkServer).to receive(:start).and_return(fork_runner)

      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        config.define_singleton_method(:fork_server) { true }
        write_timing_report(dir, "spec/foo_spec.rb" => 2.0)
        write_boot_report(dir, 1.0)
        engine = build_engine
        allow(engine).to receive(:prioritized_tests_for).and_return(["spec/foo_spec.rb"])

        expect(resolved_timeouts(config, engine:, integration:)).to eq([9.0])
      end
    end

    it "never caps the timeout below the measured baseline" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        config.define_singleton_method(:max_timeout) { 30.0 }
        write_timing_report(dir, "spec/foo_spec.rb" => 20.0)
        write_boot_report(dir, 15.0) # baseline 35s, calibrated 105s

        expect(resolved_timeouts(config)).to eq([37.0])
      end
    end

    it "warns once per run when the measured baseline exceeds max_timeout" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        config.define_singleton_method(:max_timeout) { 30.0 }
        write_timing_report(dir, "spec/foo_spec.rb" => 20.0)
        write_boot_report(dir, 15.0)
        warnings = []
        engine = build_engine
        allow(engine).to receive(:warn) { |message| warnings << message }

        resolved_timeouts(config, mutants: [build_mutant(:pending, "Foo#bar"), build_mutant(:pending, "Foo#baz")],
                                  engine:)

        expect(warnings).to eq(
          ["henitai: measured test baseline of 35.0s exceeds max_timeout (30.0s); using 37.0s instead"]
        )
      end
    end

    it "does not warn when the baseline fits within max_timeout" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        config.define_singleton_method(:max_timeout) { 30.0 }
        write_timing_report(dir, "spec/foo_spec.rb" => 20.0)
        engine = build_engine
        allow(engine).to receive(:warn)

        resolved_timeouts(config, engine:)

        expect(engine).not_to have_received(:warn)
      end
    end

    it "keeps a fixed timeout untouched even when the baseline exceeds max_timeout" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: true)
        config.define_singleton_method(:max_timeout) { 30.0 }
        write_timing_report(dir, "spec/foo_spec.rb" => 20.0)
        write_boot_report(dir, 15.0)

        expect(resolved_timeouts(config)).to eq([12.5])
      end
    end

    it "does not warn about max_timeout when the timeout is a fixed config value" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: true)
        config.define_singleton_method(:max_timeout) { 30.0 }
        write_timing_report(dir, "spec/foo_spec.rb" => 20.0)
        write_boot_report(dir, 15.0)
        engine = build_engine
        allow(engine).to receive(:warn)

        resolved_timeouts(config, engine:)

        expect(engine).not_to have_received(:warn)
      end
    end

    it "passes a calibrated per-mutant timeout when mutation.timeout is unset" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        write_timing_report(dir, "spec/foo_spec.rb" => 2.0)

        expect(resolved_timeouts(config)).to eq([6.0])
      end
    end

    it "passes the fixed config timeout untouched when mutation.timeout is set" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: true)
        write_timing_report(dir, "spec/foo_spec.rb" => 2.0)

        expect(resolved_timeouts(config)).to eq([12.5])
      end
    end

    it "clamps a calibrated timeout above the configured ceiling" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        config.define_singleton_method(:max_timeout) { 30.0 }
        write_timing_report(dir, "spec/foo_spec.rb" => 20.0) # 20 * 3.0 = 60s calibrated

        expect(resolved_timeouts(config)).to eq([30.0])
      end
    end

    it "falls back to the default timeout when timing data is missing" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        engine = build_engine
        allow(engine).to receive(:warn)

        expect(resolved_timeouts(config, engine:)).to eq([Henitai::Configuration::DEFAULT_TIMEOUT])
      end
    end

    it "warns exactly once per run when calibration is unavailable" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        warnings = []
        engine = build_engine
        allow(engine).to receive(:warn) { |message| warnings << message }

        resolved_timeouts(config, mutants: [build_mutant(:pending, "Foo#bar"), build_mutant(:pending, "Foo#baz")],
                                  engine:)

        expect(warnings.grep(/Timeout calibration unavailable/).size).to eq(1)
      end
    end
  end

  it "wires the prioritizer timing source from the reports dir" do
    Dir.mktmpdir do |dir|
      config = Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries).new(12.5, dir, 1, 3)
      File.write(
        File.join(dir, "henitai_per_test.json"),
        JSON.dump("spec/foo_spec.rb" => { "coverage" => {}, "duration" => 0.5 })
      )
      captured = nil
      allow(Henitai::TestPrioritizer).to receive(:new).and_wrap_original do |original, **kwargs|
        captured = kwargs[:timing_source]
        original.call(**kwargs)
      end

      build_engine.run([build_mutant(:pending, "Foo#bar")], build_integration, config)

      expect(captured.call).to eq("spec/foo_spec.rb" => 0.5)
    end
  end

  def with_env(key, value)
    original = ENV.fetch(key, nil)
    ENV[key] = value
    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end

  def with_temp_reports_dir(&block)
    Dir.mktmpdir do |dir|
      block.call(dir)
    end
  end

  def write_flaky_registry(dir, files)
    Henitai::FlakyTestRegistry.new(files).write(File.join(dir, Henitai::FlakyTestRegistry::FILE_NAME))
  end

  def flaky_config(reports_dir, max_retries: 3)
    Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries, :flaky_detection)
          .new(12.5, reports_dir, 1, max_retries, true)
  end

  def build_located_mutant(expression, file:, line:)
    Struct.new(:status, :subject, :location, :covered_by, :tests_completed) do
      def pending?
        status == :pending
      end
    end.new(
      :pending,
      build_subject(expression),
      {
        file: file,
        start_line: line,
        end_line: line
      }
    )
  end

  def write_per_test_coverage_report(reports_dir, coverage)
    File.write(File.join(reports_dir, "henitai_per_test.json"), coverage.to_json)
  end

  it "runs only pending mutants" do
    pending = build_mutant(:pending, "Foo#bar")
    ignored = build_mutant(:ignored, "Foo#baz")
    integration = build_integration

    build_engine.run([pending, ignored], integration, build_config)

    expect(integration.calls.slice(:select_tests, :spawn_mutant)).to eq(
      select_tests: 1,
      spawn_mutant: 1
    )
  end

  it "updates pending mutant statuses from the integration result" do
    pending = build_mutant(:pending, "Foo#bar")
    ignored = build_mutant(:ignored, "Foo#baz")

    result = build_engine.run([pending, ignored], build_integration, build_config)

    expect(result.map(&:status)).to eq(%i[killed ignored])
  end

  [1, 2].each do |jobs|
    it "marks mutants as no coverage when test exclusions remove every selected test (jobs=#{jobs})" do
      mutants = [build_mutant(:pending, "Foo#bar"), build_mutant(:pending, "Foo#baz")]
      integration = build_integration
      config = build_config(jobs:)
      config.define_singleton_method(:test_excludes) { ["spec/foo_spec.rb"] }

      build_engine.run(mutants, integration, config)

      expect(
        [mutants.map(&:status), mutants.map(&:covered_by), mutants.map(&:tests_completed),
         integration.calls[:spawn_mutant]]
      ).to eq([%i[no_coverage no_coverage], [[], []], [0, 0], 0])
    end
  end

  it "reports progress for pending mutants when a reporter is provided" do
    pending = build_mutant(:pending, "Foo#bar")
    skipped = build_mutant(:ignored, "Foo#baz")
    progress = recorder

    build_engine.run([pending, skipped], build_integration, build_config, progress_reporter: progress)

    expect(progress.calls).to eq([:killed])
  end

  it "reports progress for a mutant without coverage" do
    pending = build_mutant(:pending, "Foo#bar")
    progress = recorder
    config = build_config
    config.define_singleton_method(:test_excludes) { ["spec/foo_spec.rb"] }

    build_engine.run([pending], build_integration, config, progress_reporter: progress)

    expect(progress.calls).to eq([:no_coverage])
  end

  it "runs first the test file that killed an earlier mutant in this run" do
    mutants = [build_mutant(:pending, "Foo#bar"), build_mutant(:pending, "Foo#baz")]
    integration = build_integration.answer(
      outcome(:killed, killing_tests: [File.expand_path("spec/b_spec.rb")]), outcome(:survived)
    )
    allow(integration).to receive(:select_tests).and_return(%w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb])

    build_engine.run(mutants, integration, build_config)

    expect(integration.calls[:last_test_files]).to eq(%w[spec/b_spec.rb spec/a_spec.rb spec/c_spec.rb])
  end

  it "runs last the test file that hung for an earlier mutant of the same subject" do
    mutants = [build_mutant(:pending, "Foo#bar"), build_mutant(:pending, "Foo#bar")]
    integration = build_integration.answer(
      outcome(:timeout, hanging_test: File.expand_path("spec/b_spec.rb")), outcome(:survived)
    )
    allow(integration).to receive(:select_tests).and_return(%w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb])

    build_engine.run(mutants, integration, build_config)

    expect(integration.calls[:last_test_files]).to eq(%w[spec/a_spec.rb spec/c_spec.rb spec/b_spec.rb])
  end

  it "counts only kills toward the order, not survivors or timeouts" do
    mutants = 3.times.map { |index| build_mutant(:pending, "Foo#bar#{index}") }
    integration = build_integration.answer(
      outcome(:timeout, killing_tests: [File.expand_path("spec/b_spec.rb")]), outcome(:survived), outcome(:survived)
    )
    allow(integration).to receive(:select_tests).and_return(%w[spec/a_spec.rb spec/b_spec.rb])

    build_engine.run(mutants, integration, build_config)

    expect(integration.calls[:last_test_files]).to eq(%w[spec/a_spec.rb spec/b_spec.rb])
  end

  describe "flaky-test retries" do
    def run_with_flaky(outcome, flaky: ["spec/foo_spec.rb"], max_retries: 3, engine: build_engine)
      pending = build_mutant(:pending, "Foo#bar")
      integration = build_integration.answer(outcome)

      with_temp_reports_dir do |dir|
        write_flaky_registry(dir, flaky) if flaky
        engine.run([pending], integration, flaky_config(dir, max_retries:))
      end

      [pending.status, integration.calls[:spawn_mutant]]
    end

    it "never retries a survived mutant" do
      expect(run_with_flaky(outcome(:survived))).to eq([:survived, 1])
    end

    it "retries a kill whose killing tests are all flaky, up to the configured budget" do
      killed = outcome(:killed, killing_tests: ["spec/foo_spec.rb"])

      expect(run_with_flaky(killed, max_retries: 2)).to eq([:killed, 3])
    end

    it "does not retry a kill when a killing test is stable" do
      killed = outcome(:killed, killing_tests: ["spec/foo_spec.rb", "spec/stable_spec.rb"])

      expect(run_with_flaky(killed)).to eq([:killed, 1])
    end

    it "does not retry any kill when no flaky-test registry exists" do
      killed = outcome(:killed, killing_tests: ["spec/foo_spec.rb"])

      expect(run_with_flaky(killed, flaky: nil)).to eq([:killed, 1])
    end

    it "warns with the flaky test files when killed mutants are re-checked" do
      engine = build_engine
      allow(engine).to receive(:warn)

      run_with_flaky(outcome(:killed, killing_tests: ["spec/foo_spec.rb"]), max_retries: 1, engine:)

      expect(engine).to have_received(:warn).with(/Flaky-test mitigation: 1 killed mutant\(s\).*foo_spec\.rb/)
    end

    it "does not warn when no killed mutant is re-checked" do
      expect { run_with_flaky(outcome(:survived)) }.not_to output(/Flaky-test mitigation:/).to_stderr
    end

    it "hands the known flaky tests to the worker runner" do
      stub_worker_runner

      run_with_flaky(outcome(:killed))

      expect(Henitai::ProcessWorkerRunner).to have_received(:new).with(
        hash_including(flaky_tests: satisfy { |registry| registry.flaky?("spec/foo_spec.rb") })
      )
    end
  end

  describe "fork server" do
    let(:fork_runner) do
      instance_double(Henitai::ForkServer::MutantRunner, stop: nil, active?: true, runtime: :served_runtime)
    end

    def run_with_fork_server(jobs)
      runner = stub_worker_runner
      allow(Henitai::ForkServer).to receive(:start).and_return(fork_runner)
      config = Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries, :fork_server)
                     .new(12.5, "coverage", jobs, 3, true)
      mutants = [build_mutant(:pending, "Foo#bar")]
      engine = build_engine
      allow(engine).to receive(:prioritized_tests_for).and_return(["spec/foo_spec.rb"])
      engine.run(mutants, instance_double(Henitai::Integration::Rspec, fork_server_supported?: true), config)
      [runner, mutants, config]
    end

    [1, 2].each do |jobs|
      it "runs the worker runner on the server's runtime and runner with jobs=#{jobs}", :aggregate_failures do
        runner, mutants, config = run_with_fork_server(jobs)

        expect(Henitai::ProcessWorkerRunner).to have_received(:new).with(hash_including(runtime: :served_runtime))
        expect(runner).to have_received(:run)
          .with(mutants, fork_runner, config, anything, test_file_resolver: anything, timeout_resolver: anything,
                                                        control_run: nil)
      end
    end

    # The server boots the suite once for every slot; suite code reading the
    # slot at boot sees slot 0, as a one-slot child does.
    it "boots the server with worker slot 0 exported" do
      slot_at_boot = :unset
      allow(Henitai::ForkServer).to receive(:start) do
        slot_at_boot = ENV.fetch("HENITAI_WORKER_SLOT", nil)
        fork_runner
      end
      stub_worker_runner
      config = Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries, :fork_server)
                     .new(12.5, "coverage", 2, 3, true)
      engine = build_engine
      allow(engine).to receive(:prioritized_tests_for).and_return(["spec/foo_spec.rb"])

      engine.run([build_mutant(:pending, "Foo#bar")],
                 instance_double(Henitai::Integration::Rspec, fork_server_supported?: true), config)

      expect(slot_at_boot).to eq("0")
    end

    it "stops the server after the run" do
      run_with_fork_server(1)

      expect(fork_runner).to have_received(:stop)
    end
  end

  it "filters candidate tests by per-test coverage before executing a mutant" do
    pending = build_located_mutant("Foo#bar", file: "lib/foo.rb", line: 3)
    integration = build_integration

    with_temp_reports_dir do |reports_dir|
      write_per_test_coverage_report(
        reports_dir,
        {
          "spec/covered_spec.rb" => {
            File.expand_path("lib/foo.rb") => [3]
          },
          "spec/uncovered_spec.rb" => {
            File.expand_path("lib/foo.rb") => [8]
          }
        }
      )

      config = Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries).new(
        12.5, reports_dir, 1, 3
      )

      allow(integration).to receive_messages(
        select_tests: %w[spec/covered_spec.rb spec/uncovered_spec.rb],
        test_files: %w[spec/covered_spec.rb spec/uncovered_spec.rb]
      )

      build_engine.run([pending], integration, config)
    end

    expect(integration.calls[:last_test_files]).to eq(["spec/covered_spec.rb"])
  end

  it "runs a test covering the mutant even when name matching would not select it" do
    pending = build_located_mutant("Foo#bar", file: "lib/foo.rb", line: 3)
    integration = build_integration

    with_temp_reports_dir do |reports_dir|
      write_per_test_coverage_report(
        reports_dir,
        { "spec/unrelated_name_spec.rb" => { File.expand_path("lib/foo.rb") => [3] } }
      )

      config = Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries).new(
        12.5, reports_dir, 1, 3
      )

      allow(integration).to receive_messages(
        select_tests: ["spec/foo_spec.rb"],
        test_files: %w[spec/foo_spec.rb spec/unrelated_name_spec.rb]
      )

      build_engine.run([pending], integration, config)
    end

    expect(integration.calls[:last_test_files]).to eq(["spec/unrelated_name_spec.rb"])
  end

  it "records the selected tests on the mutant for report serialization" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration

    allow(integration).to receive(:select_tests).and_return(
      %w[spec/covered_spec.rb spec/other_spec.rb]
    )

    build_engine.run([pending], integration, build_config)

    expect([pending.covered_by, pending.tests_completed]).to eq(
      [%w[spec/covered_spec.rb spec/other_spec.rb], 2]
    )
  end

  def artifacts_config(reports_dir = "artifacts")
    Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries).new(12.5, reports_dir, 1, 3)
  end

  it "falls back to reports when the configured reports dir is blank" do
    integration = build_integration

    build_engine.run([build_mutant(:pending, "Foo#bar")], integration, artifacts_config(""))

    expect(integration.calls[:env]["HENITAI_COVERAGE_DIR"]).to eq(File.join("reports", "mutation-coverage"))
  end

  it "exposes the configured reports dir to the children" do
    integration = build_integration

    build_engine.run([build_mutant(:pending, "Foo#bar")], integration, artifacts_config)

    expect(integration.calls[:env]["HENITAI_REPORTS_DIR"]).to eq("artifacts")
  end

  it "exposes the configured coverage dir to the children" do
    integration = build_integration

    build_engine.run([build_mutant(:pending, "Foo#bar")], integration, artifacts_config)

    expect(integration.calls[:env]["HENITAI_COVERAGE_DIR"]).to eq("artifacts/mutation-coverage")
  end

  it "restores the reports dir environment variable after execution" do
    with_env("HENITAI_REPORTS_DIR", "preexisting") do
      build_engine.run([build_mutant(:pending, "Foo#bar")], build_integration, artifacts_config)

      expect(ENV.fetch("HENITAI_REPORTS_DIR", nil)).to eq("preexisting")
    end
  end

  it "restores the coverage dir environment variable after execution" do
    with_env("HENITAI_COVERAGE_DIR", "preexisting") do
      build_engine.run([build_mutant(:pending, "Foo#bar")], build_integration, artifacts_config)

      expect(ENV.fetch("HENITAI_COVERAGE_DIR", nil)).to eq("preexisting")
    end
  end
end
