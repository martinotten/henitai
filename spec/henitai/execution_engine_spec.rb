# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

IntegrationSpy = Class.new do
  attr_reader :calls

  def initialize
    @calls = Hash.new(0)
  end

  def select_tests(subject)
    @calls[:select_tests] += 1
    @calls[:last_subject] = subject.expression
    ["spec/foo_spec.rb"]
  end

  def test_files
    ["spec/foo_spec.rb"]
  end

  def run_mutant(mutant:, test_files:, timeout:)
    @calls[:run_mutant] += 1
    @calls[:last_test_files] = test_files
    @calls[:last_timeout] = timeout
    @calls[:worker_slot] = ENV.fetch("HENITAI_WORKER_SLOT", nil)
    mutant.status = :killed
  end
end

RSpec.describe Henitai::ExecutionEngine do
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
    IntegrationSpy.new
  end

  def build_config
    Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries).new(
      12.5,
      "coverage",
      1,
      3
    )
  end

  describe "control runs" do
    def config_with_control_runs(enabled)
      Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries, :control_runs).new(12.5, "coverage", 1, 3, enabled)
    end

    def stub_control_run(stats)
      control_run = instance_double(Henitai::ControlRun, verify: stats)
      allow(Henitai::ControlRun).to receive(:new).and_return(control_run)
      control_run
    end

    it "verifies the executed mutants when control runs are enabled" do
      mutant = build_mutant(:pending, "Foo#bar")
      control_run = stub_control_run(verified: 1, failed: 0, reclassified: 0)

      described_class.new.run([mutant], build_integration, config_with_control_runs(true))

      expect(control_run).to have_received(:verify).with([mutant])
    end

    it "does not verify when control runs are disabled" do
      mutant = build_mutant(:pending, "Foo#bar")
      stub_control_run(verified: 0, failed: 0, reclassified: 0)

      described_class.new.run([mutant], build_integration, config_with_control_runs(false))

      expect(Henitai::ControlRun).not_to have_received(:new)
    end

    it "warns when a control run reclassifies verdicts" do
      mutant = build_mutant(:pending, "Foo#bar")
      stub_control_run(verified: 3, failed: 1, reclassified: 4)

      expect { described_class.new.run([mutant], build_integration, config_with_control_runs(true)) }
        .to output(/control runs failed for 1 of 3 subjects; 4 detected verdicts reclassified as CompileError/)
        .to_stderr
    end
  end

  describe "HENITAI_WORKER_SLOT on the linear path" do
    around do |example|
      original = ENV.fetch("HENITAI_WORKER_SLOT", nil)
      ENV["HENITAI_WORKER_SLOT"] = "sentinel"
      example.run
    ensure
      original.nil? ? ENV.delete("HENITAI_WORKER_SLOT") : ENV["HENITAI_WORKER_SLOT"] = original
    end

    it "exposes slot 0 to every child" do
      mutant = build_mutant(:pending, "Foo#bar")
      integration = build_integration

      described_class.new.run([mutant], integration, build_config)

      expect(integration.calls[:worker_slot]).to eq("0")
    end

    it "restores the variable after the run" do
      mutant = build_mutant(:pending, "Foo#bar")

      described_class.new.run([mutant], build_integration, build_config)

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

    it "includes the measured suite boot time in the calibrated timeout" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        write_timing_report(dir, "spec/foo_spec.rb" => 2.0)
        write_boot_report(dir, 1.0)
        integration = build_integration

        described_class.new.run([build_mutant(:pending, "Foo#bar")], integration, config)

        expect(integration.calls[:last_timeout]).to eq(9.0)
      end
    end

    it "never caps the timeout below the measured baseline" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        config.define_singleton_method(:max_timeout) { 30.0 }
        write_timing_report(dir, "spec/foo_spec.rb" => 20.0)
        write_boot_report(dir, 15.0) # baseline 35s, calibrated 105s
        integration = build_integration

        described_class.new.run([build_mutant(:pending, "Foo#bar")], integration, config)

        expect(integration.calls[:last_timeout]).to eq(37.0)
      end
    end

    it "warns once per run when the measured baseline exceeds max_timeout" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        config.define_singleton_method(:max_timeout) { 30.0 }
        write_timing_report(dir, "spec/foo_spec.rb" => 20.0)
        write_boot_report(dir, 15.0)
        mutants = [build_mutant(:pending, "Foo#bar"), build_mutant(:pending, "Foo#baz")]
        warnings = []
        engine = described_class.new
        allow(engine).to receive(:warn) { |message| warnings << message }

        engine.run(mutants, build_integration, config)

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
        engine = described_class.new
        allow(engine).to receive(:warn)

        engine.run([build_mutant(:pending, "Foo#bar")], build_integration, config)

        expect(engine).not_to have_received(:warn)
      end
    end

    it "keeps a fixed timeout untouched even when the baseline exceeds max_timeout" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: true)
        config.define_singleton_method(:max_timeout) { 30.0 }
        write_timing_report(dir, "spec/foo_spec.rb" => 20.0)
        write_boot_report(dir, 15.0)
        integration = build_integration

        described_class.new.run([build_mutant(:pending, "Foo#bar")], integration, config)

        expect(integration.calls[:last_timeout]).to eq(12.5)
      end
    end

    it "does not warn about max_timeout when the timeout is a fixed config value" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: true)
        config.define_singleton_method(:max_timeout) { 30.0 }
        write_timing_report(dir, "spec/foo_spec.rb" => 20.0)
        write_boot_report(dir, 15.0)
        engine = described_class.new
        allow(engine).to receive(:warn)

        engine.run([build_mutant(:pending, "Foo#bar")], build_integration, config)

        expect(engine).not_to have_received(:warn)
      end
    end

    it "passes a calibrated per-mutant timeout when mutation.timeout is unset" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        write_timing_report(dir, "spec/foo_spec.rb" => 2.0)
        integration = build_integration

        described_class.new.run([build_mutant(:pending, "Foo#bar")], integration, config)

        expect(integration.calls[:last_timeout]).to eq(6.0)
      end
    end

    it "passes the fixed config timeout untouched when mutation.timeout is set" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: true)
        write_timing_report(dir, "spec/foo_spec.rb" => 2.0)
        integration = build_integration

        described_class.new.run([build_mutant(:pending, "Foo#bar")], integration, config)

        expect(integration.calls[:last_timeout]).to eq(12.5)
      end
    end

    it "clamps a calibrated timeout above the configured ceiling" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        config.define_singleton_method(:max_timeout) { 30.0 }
        write_timing_report(dir, "spec/foo_spec.rb" => 20.0) # 20 * 3.0 = 60s calibrated
        integration = build_integration

        described_class.new.run([build_mutant(:pending, "Foo#bar")], integration, config)

        expect(integration.calls[:last_timeout]).to eq(30.0)
      end
    end

    it "falls back to the default timeout when timing data is missing" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        integration = build_integration
        engine = described_class.new
        allow(engine).to receive(:warn)

        engine.run([build_mutant(:pending, "Foo#bar")], integration, config)

        expect(integration.calls[:last_timeout]).to eq(Henitai::Configuration::DEFAULT_TIMEOUT)
      end
    end

    it "warns exactly once per run when calibration is unavailable" do
      Dir.mktmpdir do |dir|
        config = build_calibrating_config(dir, timeout_configured: false)
        mutants = [build_mutant(:pending, "Foo#bar"), build_mutant(:pending, "Foo#baz")]
        warnings = []
        engine = described_class.new
        allow(engine).to receive(:warn) { |message| warnings << message }

        engine.run(mutants, build_integration, config)

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

      described_class.new.run([build_mutant(:pending, "Foo#bar")], build_integration, config)

      expect(captured.call).to eq("spec/foo_spec.rb" => 0.5)
    end
  end

  it "keeps the conservative single-worker fallback when jobs is nil" do
    pending_a = build_mutant(:pending, "Foo#bar")
    pending_b = build_mutant(:pending, "Foo#baz")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries).new(
      12.5,
      "coverage",
      nil,
      3
    )

    allow(integration).to receive(:select_tests).and_return(["spec/foo_spec.rb"])
    allow(integration).to receive(:run_mutant) do |mutant:, **_kwargs|
      mutant.status = :killed
    end
    allow(Henitai::ProcessWorkerRunner).to receive(:new)

    described_class.new.run([pending_a, pending_b], integration, config)

    expect(Henitai::ProcessWorkerRunner).not_to have_received(:new)
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
    Struct.new(:status, :subject, :location) do
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

    described_class.new.run([pending, ignored], integration, build_config)

    expect(integration.calls.slice(:select_tests, :run_mutant)).to eq(
      select_tests: 1,
      run_mutant: 1
    )
  end

  it "updates pending mutant statuses from the integration result" do
    pending = build_mutant(:pending, "Foo#bar")
    ignored = build_mutant(:ignored, "Foo#baz")
    integration = build_integration

    result = described_class.new.run([pending, ignored], integration, build_config)

    expect(result.map(&:status)).to eq(%i[killed ignored])
  end

  it "marks a mutant as no coverage when test exclusions remove every selected test" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    config = build_config
    config.define_singleton_method(:test_excludes) { ["spec/foo_spec.rb"] }

    described_class.new.run([pending], integration, config)

    expect(
      [pending.status, pending.covered_by, pending.tests_completed, integration.calls[:run_mutant]]
    ).to eq([:no_coverage, [], 0, 0])
  end

  it "does not spawn parallel workers when test exclusions remove every selected test" do
    mutants = [build_mutant(:pending, "Foo#bar"), build_mutant(:pending, "Foo#baz")]
    integration = instance_double(Henitai::Integration::Rspec)
    spawn_calls = 0
    allow(integration).to receive(:select_tests).and_return(["spec/foo_spec.rb"])
    allow(integration).to receive(:spawn_mutant) do
      spawn_calls += 1
      raise "should not spawn"
    end
    config = build_config
    config.jobs = 2
    config.define_singleton_method(:test_excludes) { ["spec/foo_spec.rb"] }

    described_class.new.run(mutants, integration, config)

    expect([mutants.map(&:status), spawn_calls]).to eq([%i[no_coverage no_coverage], 0])
  end

  it "reports progress for pending mutants when a reporter is provided" do
    pending = build_mutant(:pending, "Foo#bar")
    skipped = build_mutant(:ignored, "Foo#baz")
    integration = build_integration
    progress = Struct.new(:calls) do
      def progress(mutant, **_)
        calls << mutant.status
      end
    end.new([])

    described_class.new.run([pending, skipped], integration, build_config, progress_reporter: progress)

    expect(progress.calls).to eq([:killed])
  end

  it "prioritizes tests that have already killed other mutants" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir, :jobs, :history).new(
      12.5,
      "coverage",
      1,
      {
        "spec/b_spec.rb" => 5,
        "spec/a_spec.rb" => 1
      }
    )

    allow(integration).to receive(:select_tests).and_return(
      %w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb]
    )

    described_class.new.run([pending], integration, config)

    expect(integration.calls[:last_test_files]).to eq(
      %w[spec/b_spec.rb spec/a_spec.rb spec/c_spec.rb]
    )
  end

  it "never retries a survived mutant" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    call_count = 0

    allow(integration).to receive(:select_tests).and_return(["spec/foo_spec.rb"])
    allow(integration).to receive(:run_mutant) do
      call_count += 1
      :survived
    end

    with_temp_reports_dir do |dir|
      write_flaky_registry(dir, ["spec/foo_spec.rb"])
      described_class.new.run([pending], integration, flaky_config(dir))
    end

    expect([pending.status, call_count]).to eq([:survived, 1])
  end

  it "retries a kill whose killing tests are all flaky, up to the configured budget" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    call_count = 0
    killed = Struct.new(:status, :killing_tests).new(:killed, ["spec/foo_spec.rb"])

    allow(integration).to receive(:select_tests).and_return(["spec/foo_spec.rb"])
    allow(integration).to receive(:run_mutant) do
      call_count += 1
      killed
    end

    with_temp_reports_dir do |dir|
      write_flaky_registry(dir, ["spec/foo_spec.rb"])
      described_class.new.run([pending], integration, flaky_config(dir, max_retries: 2))
    end

    expect([pending.status, call_count]).to eq([:killed, 3])
  end

  it "does not retry a kill when a killing test is stable" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    call_count = 0
    killed = Struct.new(:status, :killing_tests).new(:killed, ["spec/foo_spec.rb", "spec/stable_spec.rb"])

    allow(integration).to receive(:select_tests).and_return(["spec/foo_spec.rb"])
    allow(integration).to receive(:run_mutant) do
      call_count += 1
      killed
    end

    with_temp_reports_dir do |dir|
      write_flaky_registry(dir, ["spec/foo_spec.rb"])
      described_class.new.run([pending], integration, flaky_config(dir))
    end

    expect(call_count).to eq(1)
  end

  it "does not retry any kill when no flaky-test registry exists" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    call_count = 0
    killed = Struct.new(:status, :killing_tests).new(:killed, ["spec/foo_spec.rb"])

    allow(integration).to receive(:select_tests).and_return(["spec/foo_spec.rb"])
    allow(integration).to receive(:run_mutant) do
      call_count += 1
      killed
    end

    with_temp_reports_dir do |dir|
      described_class.new.run([pending], integration, flaky_config(dir))
    end

    expect(call_count).to eq(1)
  end

  it "warns with the flaky test files when killed mutants are re-checked" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    engine = described_class.new
    killed = Struct.new(:status, :killing_tests).new(:killed, ["spec/foo_spec.rb"])

    allow(integration).to receive_messages(select_tests: ["spec/foo_spec.rb"], run_mutant: killed)
    allow(engine).to receive(:warn)

    with_temp_reports_dir do |dir|
      write_flaky_registry(dir, ["spec/foo_spec.rb"])
      engine.run([pending], integration, flaky_config(dir, max_retries: 1))
    end

    expect(engine).to have_received(:warn).with(/Flaky-test mitigation: 1 killed mutant\(s\).*foo_spec\.rb/)
  end

  it "does not warn when no killed mutant is re-checked" do
    mutants = 25.times.map do |index|
      build_mutant(:pending, "Foo#bar#{index}")
    end
    integration = build_integration

    allow(integration).to receive_messages(select_tests: ["spec/foo_spec.rb"], run_mutant: :survived)

    with_temp_reports_dir do |dir|
      write_flaky_registry(dir, ["spec/foo_spec.rb"])
      expect do
        described_class.new.run(mutants, integration, flaky_config(dir))
      end.not_to output(/Flaky-test mitigation:/).to_stderr
    end
  end

  it "keeps a single pending mutant on the linear path even with parallel jobs configured" do
    pending = build_mutant(:pending, "Foo#bar")
    ignored = build_mutant(:ignored, "Foo#baz")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir, :jobs).new(12.5, "coverage", 2)
    thread_ids = []

    allow(integration).to receive(:run_mutant) do |mutant:, **_kwargs|
      thread_ids << Thread.current.object_id
      mutant.status = :killed
    end

    described_class.new.run([pending, ignored], integration, config)

    expect(thread_ids).to eq([Thread.current.object_id])
  end

  it "treats zero jobs as linear execution" do
    first = build_mutant(:pending, "Foo#bar")
    second = build_mutant(:pending, "Foo#baz")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir, :jobs).new(12.5, "coverage", 0)

    described_class.new.run([first, second], integration, config)

    expect(integration.calls[:run_mutant]).to eq(2)
  end

  it "keeps jobs=1 on the linear execution path" do
    first = build_mutant(:pending, "Foo#bar")
    second = build_mutant(:pending, "Foo#baz")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir, :jobs).new(12.5, "coverage", 1)
    thread_ids = []

    allow(integration).to receive(:run_mutant) do |mutant:, **_kwargs|
      thread_ids << Thread.current.object_id
      mutant.status = :killed
    end

    described_class.new.run([first, second], integration, config)

    expect(thread_ids.uniq.size).to eq(1)
  end

  it "runs linearly when jobs are not configured" do
    first = build_mutant(:pending, "Foo#bar")
    second = build_mutant(:pending, "Foo#baz")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir, :jobs).new(12.5, "coverage", nil)
    thread_ids = []

    allow(integration).to receive(:run_mutant) do |mutant:, **_kwargs|
      thread_ids << Thread.current.object_id
      mutant.status = :killed
    end

    described_class.new.run([first, second], integration, config)

    expect(thread_ids.uniq.size).to eq(1)
  end

  it "returns the status from a scenario result object" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    config = build_config
    result = Struct.new(:status).new(:killed)

    allow(integration).to receive(:run_mutant).and_return(result)

    described_class.new.run([pending], integration, config)

    expect(pending.status).to eq(:killed)
  end

  it "reports flaky-test re-checks that happened on the parallel path" do
    engine = described_class.new
    mutants = 4.times.map { |index| build_mutant(:pending, "Foo#bar#{index}") }
    integration = build_integration
    runner = instance_double(Henitai::ProcessWorkerRunner, flaky_retry_count: 1)
    allow(runner).to receive(:run).and_return([])
    allow(Henitai::ProcessWorkerRunner).to receive(:new).and_return(runner)
    allow(engine).to receive(:warn)

    with_temp_reports_dir do |dir|
      write_flaky_registry(dir, ["spec/foo_spec.rb"])
      engine.run(mutants, integration, flaky_config(dir).tap { |config| config.jobs = 2 })
    end

    expect(engine).to have_received(:warn).with(/Flaky-test mitigation: 1 killed mutant\(s\)/)
  end

  it "filters candidate tests by per-test coverage before executing a mutant" do
    pending = build_located_mutant("Foo#bar", file: "lib/foo.rb", line: 3)
    integration = build_integration
    observed_tests = nil

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

      config = Struct.new(:timeout, :reports_dir, :jobs, :history).new(
        12.5,
        reports_dir,
        1,
        {}
      )

      allow(integration).to receive_messages(
        select_tests: %w[spec/covered_spec.rb spec/uncovered_spec.rb],
        test_files: %w[spec/covered_spec.rb spec/uncovered_spec.rb]
      )
      allow(integration).to receive(:run_mutant) do |mutant:, test_files:, **_kwargs|
        observed_tests = test_files
        mutant.status = :killed
      end

      described_class.new.run([pending], integration, config)
    end

    expect(observed_tests).to eq(["spec/covered_spec.rb"])
  end

  it "runs a test covering the mutant even when name matching would not select it" do
    pending = build_located_mutant("Foo#bar", file: "lib/foo.rb", line: 3)
    integration = build_integration
    observed_tests = nil

    with_temp_reports_dir do |reports_dir|
      write_per_test_coverage_report(
        reports_dir,
        { "spec/unrelated_name_spec.rb" => { File.expand_path("lib/foo.rb") => [3] } }
      )

      config = Struct.new(:timeout, :reports_dir, :jobs, :history).new(
        12.5, reports_dir, 1, {}
      )

      allow(integration).to receive_messages(
        select_tests: ["spec/foo_spec.rb"],
        test_files: %w[spec/foo_spec.rb spec/unrelated_name_spec.rb]
      )
      allow(integration).to receive(:run_mutant) do |mutant:, test_files:, **_kwargs|
        observed_tests = test_files
        mutant.status = :killed
      end

      described_class.new.run([pending], integration, config)
    end

    expect(observed_tests).to eq(["spec/unrelated_name_spec.rb"])
  end

  it "records the selected tests on the mutant for report serialization" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration

    allow(integration).to receive(:select_tests).and_return(
      %w[spec/covered_spec.rb spec/other_spec.rb]
    )
    allow(integration).to receive(:run_mutant) do |mutant:, **_kwargs|
      mutant.status = :killed
    end

    described_class.new.run([pending], integration, build_config)

    expect([pending.covered_by, pending.tests_completed]).to eq(
      [%w[spec/covered_spec.rb spec/other_spec.rb], 2]
    )
  end

  it "falls back to reports when the configured reports dir is blank" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir, :jobs).new(12.5, "", 1)
    observed_coverage_dir = nil

    allow(integration).to receive(:run_mutant) do |mutant:, **_kwargs|
      observed_coverage_dir = ENV.fetch("HENITAI_COVERAGE_DIR", nil)
      mutant.status = :killed
    end

    described_class.new.run([pending], integration, config)

    expect(observed_coverage_dir).to eq(
      File.join("reports", "mutation-coverage")
    )
  end

  it "exposes the configured reports dir to the integration run" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir).new(12.5, "artifacts")
    observed_reports_dir = nil

    allow(integration).to receive(:run_mutant) do |mutant:, **_kwargs|
      observed_reports_dir = ENV.fetch("HENITAI_REPORTS_DIR", nil)
      mutant.status = :killed
    end

    described_class.new.run([pending], integration, config)

    expect(observed_reports_dir).to eq("artifacts")
  end

  it "exposes the configured coverage dir to the integration run" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir).new(12.5, "artifacts")
    observed_coverage_dir = nil

    allow(integration).to receive(:run_mutant) do |mutant:, **_kwargs|
      observed_coverage_dir = ENV.fetch("HENITAI_COVERAGE_DIR", nil)
      mutant.status = :killed
    end

    described_class.new.run([pending], integration, config)

    expect(observed_coverage_dir).to eq("artifacts/mutation-coverage")
  end

  it "restores the reports dir environment variable after execution" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir).new(12.5, "artifacts")

    with_env("HENITAI_REPORTS_DIR", "preexisting") do
      described_class.new.run([pending], integration, config)

      expect(ENV.fetch("HENITAI_REPORTS_DIR", nil)).to eq("preexisting")
    end
  end

  it "restores the coverage dir environment variable after execution" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir).new(12.5, "artifacts")

    with_env("HENITAI_COVERAGE_DIR", "preexisting") do
      described_class.new.run([pending], integration, config)

      expect(ENV.fetch("HENITAI_COVERAGE_DIR", nil)).to eq("preexisting")
    end
  end
end
