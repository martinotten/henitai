# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Henitai::FlakyDetectionBaseline do
  let(:reports_dir) { Dir.mktmpdir }
  let(:test_files) { ["a_spec.rb", "b_spec.rb"] }
  let(:flaky_path) { File.join(reports_dir, Henitai::FlakyTestRegistry::FILE_NAME) }

  after { FileUtils.remove_entry(reports_dir) }

  # Stands in for an integration: each run_suite call records the next
  # scripted outcome map exactly like the coverage formatter does.
  def scripted_suite(runs, statuses)
    path = Henitai::TestFileOutcomes.report_path(reports_dir)
    build = method(:scenario_result)
    record = method(:recorded_outcomes)
    suite = Object.new
    suite.define_singleton_method(:run_suite) do |_test_files, **|
      outcomes = runs.shift
      next build.call(:failed) if outcomes.nil?

      record.call(outcomes).write(path)
      build.call(statuses.shift || :survived)
    end
    suite
  end

  def recorded_outcomes(outcomes)
    Henitai::TestFileOutcomes.new.tap do |recorder|
      outcomes.each do |file, outcome|
        next recorder.record_unattributed_failure if file == :unattributed

        recorder.record(file, failed: outcome == "failed")
      end
    end
  end

  def scenario_result(status, log_path: File.join(reports_dir, "suite.log"))
    Henitai::ScenarioExecutionResult.new(status:, stdout: "", stderr: "", log_path:)
  end

  def run_baseline(runs, statuses = [])
    suite = scripted_suite(runs.dup, statuses.dup)
    described_class.new(reports_dir: reports_dir).run(integration: suite, test_files:)
  end

  it "marks a file flaky when its outcome differs between the two runs" do
    registry = run_baseline([
                              { "a_spec.rb" => "passed", "b_spec.rb" => "passed" },
                              { "a_spec.rb" => "failed", "b_spec.rb" => "passed" }
                            ])

    expect(registry.all).to eq([File.expand_path("a_spec.rb")])
  end

  it "persists the flaky set to the registry file" do
    run_baseline([
                   { "a_spec.rb" => "passed", "b_spec.rb" => "passed" },
                   { "a_spec.rb" => "failed", "b_spec.rb" => "passed" }
                 ])

    expect(Henitai::FlakyTestRegistry.load(flaky_path).all).to eq([File.expand_path("a_spec.rb")])
  end

  it "reports no flaky tests when both runs agree" do
    outcomes = { "a_spec.rb" => "passed", "b_spec.rb" => "passed" }

    expect(run_baseline([outcomes, outcomes]).empty?).to be(true)
  end

  it "warns on stderr listing the detected flaky files" do
    runs = [
      { "a_spec.rb" => "passed", "b_spec.rb" => "passed" },
      { "a_spec.rb" => "failed", "b_spec.rb" => "passed" }
    ]

    expect { run_baseline(runs) }.to output(/Flaky tests detected.*a_spec\.rb/).to_stderr
  end

  it "raises CoverageError when a run records no outcomes" do
    expect { run_baseline([]) }.to raise_error(Henitai::CoverageError, /could not record suite outcomes/)
  end

  it "accepts a failing run that a flaky file explains" do
    runs = [
      { "a_spec.rb" => "passed" },
      { "a_spec.rb" => "failed" }
    ]

    expect(run_baseline(runs, %i[survived failed]).all).to eq([File.expand_path("a_spec.rb")])
  end

  it "raises CoverageError when the suite fails consistently" do
    outcomes = { "a_spec.rb" => "failed" }

    expect { run_baseline([outcomes, outcomes], %i[failed failed]) }
      .to raise_error(Henitai::CoverageError, /test suite failed/)
  end

  it "raises CoverageError when a run fails without any flaky file" do
    outcomes = { "a_spec.rb" => "passed" }

    expect { run_baseline([outcomes, outcomes], %i[survived failed]) }
      .to raise_error(Henitai::CoverageError, /test suite failed/)
  end

  it "raises CoverageError when a file fails in only one run and is missing from the other" do
    runs = [
      { "a_spec.rb" => "passed", "b_spec.rb" => "passed" },
      { "a_spec.rb" => "failed", "c_spec.rb" => "failed" }
    ]

    expect { run_baseline(runs, %i[survived failed]) }.to raise_error(Henitai::CoverageError, /test suite failed/)
  end

  it "raises CoverageError when a failing run had a failure outside any spec file" do
    runs = [
      { "a_spec.rb" => "passed" },
      { "a_spec.rb" => "failed", unattributed: true }
    ]

    expect { run_baseline(runs, %i[survived failed]) }.to raise_error(Henitai::CoverageError, /test suite failed/)
  end

  it "includes the log path and log tail when the failing run has a log" do
    log_path = File.join(reports_dir, "suite.log")
    File.write(log_path, "boot ok\nLoadError: cannot load such file -- missing\n")
    outcomes = { "a_spec.rb" => "passed" }

    expect { run_baseline([outcomes, outcomes], %i[survived failed]) }
      .to raise_error(Henitai::CoverageError, /\(see #{Regexp.escape(log_path)}\).*LoadError/m)
  end

  it "passes the configured timeout to every baseline run" do
    seen = []
    build = method(:scenario_result)
    path = Henitai::TestFileOutcomes.report_path(reports_dir)
    suite = Object.new
    suite.define_singleton_method(:run_suite) do |_test_files, timeout:|
      seen << timeout
      recorder = Henitai::TestFileOutcomes.new
      recorder.record("a_spec.rb", failed: false)
      recorder.write(path)
      build.call(:survived)
    end

    described_class.new(reports_dir:, timeout: 1200.0).run(integration: suite, test_files:)

    expect(seen).to eq([1200.0, 1200.0])
  end

  it "raises a timeout message when a baseline run times out" do
    outcomes = { "a_spec.rb" => "passed" }
    suite = scripted_suite([outcomes.dup, outcomes.dup], %i[timeout timeout])

    expect { described_class.new(reports_dir:, timeout: 1200).run(integration: suite, test_files:) }
      .to raise_error(Henitai::CoverageError, /did not finish within 1200 s/)
  end
end
