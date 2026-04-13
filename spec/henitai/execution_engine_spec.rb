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

  def run_mutant(mutant:, test_files:, timeout:)
    @calls[:run_mutant] += 1
    @calls[:last_test_files] = test_files
    @calls[:last_timeout] = timeout
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

  it "retries survived mutants up to three times" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    call_count = 0

    allow(integration).to receive(:select_tests).and_return(["spec/foo_spec.rb"])
    allow(integration).to receive(:run_mutant) do |mutant:, **_kwargs|
      call_count += 1
      mutant.status = call_count < 3 ? :survived : :killed
    end

    described_class.new.run([pending], integration, build_config)

    expect([pending.status, call_count]).to eq([:killed, 3])
  end

  it "honors a configured flaky retry budget" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    call_count = 0
    config = Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries).new(
      12.5,
      "coverage",
      1,
      1
    )

    allow(integration).to receive(:select_tests).and_return(["spec/foo_spec.rb"])
    allow(integration).to receive(:run_mutant) do |mutant:, **_kwargs|
      call_count += 1
      mutant.status = :survived
    end

    described_class.new.run([pending], integration, config)

    expect(call_count).to eq(2)
  end

  it "warns when a significant share of mutants required retries" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    engine = described_class.new

    allow(integration).to receive(:select_tests).and_return(["spec/foo_spec.rb"])
    allow(integration).to receive(:run_mutant).and_return(
      :survived,
      :survived,
      :survived,
      :survived
    )
    allow(engine).to receive(:warn)

    engine.run([pending], integration, build_config)

    expect(engine).to have_received(:warn).with(/Flaky-test mitigation:/)
  end

  it "does not warn about flaky mitigation below the retry threshold" do
    mutants = 25.times.map do |index|
      build_mutant(:pending, "Foo#bar#{index}")
    end
    integration = build_integration
    call_counts = Hash.new(0)

    allow(integration).to receive(:select_tests).and_return(["spec/foo_spec.rb"])
    allow(integration).to receive(:run_mutant) do |mutant:, **_kwargs|
      expression = mutant.subject.expression
      call_counts[expression] += 1

      if expression == "Foo#bar0" && call_counts[expression] == 1
        :survived
      else
        mutant.status = :killed
      end
    end

    expect do
      described_class.new.run(mutants, integration, build_config)
    end.not_to output(/Flaky-test mitigation:/).to_stderr
  end

  it "uses configured jobs when running mutants in parallel" do
    first = build_mutant(:pending, "Foo#bar")
    second = build_mutant(:pending, "Foo#baz")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir, :jobs).new(12.5, "coverage", 2)
    thread_ids = []

    allow(integration).to receive(:run_mutant) do |mutant:, **_kwargs|
      thread_ids << Thread.current.object_id
      sleep 0.01
      mutant.status = :killed
    end

    described_class.new.run([first, second], integration, config)

    expect(thread_ids.uniq.size).to be > 1
  end

  it "raises when a parallel worker fails" do
    first = build_mutant(:pending, "Foo#bar")
    second = build_mutant(:pending, "Foo#baz")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir, :jobs).new(12.5, "coverage", 2)

    allow(integration).to receive(:select_tests).and_return(["spec/foo_spec.rb"])
    allow(integration).to receive(:run_mutant).and_raise(StandardError, "boom")

    expect do
      described_class.new.run([first, second], integration, config)
    end.to raise_error(StandardError, "boom")
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
      sleep 0.01
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
      sleep 0.01
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

  it "formats the flaky retry ratio as a percentage" do
    engine = described_class.new
    mutants = 4.times.map { |index| build_mutant(:pending, "Foo#bar#{index}") }
    integration = build_integration
    call_counts = Hash.new(0)
    allow(engine).to receive(:warn)
    allow(integration).to receive(:select_tests).and_return(["spec/foo_spec.rb"])
    allow(integration).to receive(:run_mutant) do |mutant:, **_kwargs|
      expression = mutant.subject.expression
      call_counts[expression] += 1

      if expression == "Foo#bar0" && call_counts[expression] == 1
        Struct.new(:status).new(:survived)
      else
        Struct.new(:status).new(:killed)
      end
    end

    engine.run(mutants, integration, build_config)

    expect(engine).to have_received(:warn).with(
      "Flaky-test mitigation: 1/4 mutants required retries (25.00%)"
    )
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

      allow(integration).to receive(:select_tests).and_return(
        %w[spec/covered_spec.rb spec/uncovered_spec.rb]
      )
      allow(integration).to receive(:run_mutant) do |mutant:, test_files:, **_kwargs|
        observed_tests = test_files
        mutant.status = :killed
      end

      described_class.new.run([pending], integration, config)
    end

    expect(observed_tests).to eq(["spec/covered_spec.rb"])
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

  it "stops parallel execution when the stdin pipe is closed (docker exec disconnect)" do
    first  = build_mutant(:pending, "Foo#bar")
    second = build_mutant(:pending, "Foo#baz")
    config = Struct.new(:timeout, :reports_dir, :jobs).new(12.5, "coverage", 2)
    fake_stdin_r, fake_stdin_w = IO.pipe
    ran = []

    allow(integration = build_integration).to receive(:run_mutant) do |mutant:, **_|
      ran << mutant.subject.expression
      sleep 0.05
      mutant.status = :killed
    end

    engine = described_class.new
    allow(engine).to receive(:pipe_stdin?).and_return(true)

    t = Thread.new do
      original = $stdin
      $stdin = fake_stdin_r
      engine.run([first, second], integration, config)
    rescue Interrupt
      nil
    ensure
      $stdin = original
      fake_stdin_r.close unless fake_stdin_r.closed?
    end

    # Let workers start, then simulate docker exec disconnect
    sleep 0.01
    fake_stdin_w.close

    t.join(2)
    expect(t.alive?).to be(false)
  ensure
    fake_stdin_w.close unless fake_stdin_w.closed?
    fake_stdin_r.close unless fake_stdin_r.closed?
  end
end
