# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "henitai/integration/minitest_outcome_reporter"

RSpec.describe Henitai::Integration::MinitestOutcomeReporter do
  let(:outcomes) { Henitai::TestFileOutcomes.new }
  let(:file) { File.expand_path("test/a_test.rb") }

  def result(passed:, skipped: false, klass: "UnresolvableTest")
    instance_double(
      Minitest::Result,
      source_location: [file, 3],
      klass: klass,
      passed?: passed,
      skipped?: skipped
    )
  end

  def unlocated(source_location)
    instance_double(
      Minitest::Result,
      source_location: source_location,
      klass: "UnresolvableTest",
      passed?: false,
      skipped?: false
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
    expect { described_class.new(outcomes).record(unlocated(nil)) }.not_to raise_error
  end

  it "records no file for a failing result without a source location" do
    described_class.new(outcomes).record(unlocated(nil))

    expect(outcomes.outcomes).to be_empty
  end

  it "records a failure without a source location as unattributed" do
    described_class.new(outcomes).record(unlocated(nil))

    expect(outcomes.unattributed_failures?).to be(true)
  end

  it "skips results whose source location is not a file" do
    described_class.new(outcomes).record(unlocated(["unknown", 0]))

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
