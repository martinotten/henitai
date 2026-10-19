# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "henitai/integration/minitest_outcome_reporter"

RSpec.describe Henitai::Integration::MinitestOutcomeReporter do
  let(:outcomes) { Henitai::TestFileOutcomes.new }
  let(:file) { File.expand_path("test/a_test.rb") }

  def result(passed:, skipped: false)
    instance_double(
      Minitest::Result,
      source_location: [file, 3],
      passed?: passed,
      skipped?: skipped
    )
  end

  it "records a failing result's source file as failed" do
    described_class.new(outcomes).record(result(passed: false))

    expect(outcomes.failed_files).to eq([file])
  end

  it "records passing results as passed" do
    described_class.new(outcomes).record(result(passed: true))

    expect(outcomes.outcomes).to eq(file => "passed")
  end

  it "does not count skipped results as failed" do
    described_class.new(outcomes).record(result(passed: false, skipped: true))

    expect(outcomes.failed_files).to be_empty
  end

  it "skips results without a source location instead of crashing" do
    unlocated = instance_double(Minitest::Result, source_location: nil, passed?: false, skipped?: false)

    expect { described_class.new(outcomes).record(unlocated) }.not_to raise_error
  end

  it "records nothing for results without a source location" do
    unlocated = instance_double(Minitest::Result, source_location: nil, passed?: false, skipped?: false)

    described_class.new(outcomes).record(unlocated)

    expect(outcomes.outcomes).to be_empty
  end

  it "skips results whose source location is not a file" do
    unknown = instance_double(Minitest::Result, source_location: ["unknown", 0], passed?: false, skipped?: false)

    described_class.new(outcomes).record(unknown)

    expect(outcomes.outcomes).to be_empty
  end

  it "writes the outcomes when a report path is given" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "outcomes.json")
      reporter = described_class.new(outcomes, report_path: path, io: StringIO.new)
      reporter.record(result(passed: false))
      reporter.report

      expect(Henitai::TestFileOutcomes.load(path).failed_files).to eq([file])
    end
  end
end
