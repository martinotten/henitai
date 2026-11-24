# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "henitai/integration/minitest_outcome_reporter"

# Named at file level so its source location is this spec file.
PrerecordSpecTest = Class.new

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

  describe "on_failure" do
    def calls_for(result)
      calls = []
      described_class.new(outcomes, on_failure: -> { calls << :failed }).record(result)
      calls
    end

    it "is called for a failing result" do
      expect(calls_for(result(passed: false))).to eq([:failed])
    end

    it "is called for a failure without a source location" do
      expect(calls_for(unlocated(nil))).to eq([:failed])
    end

    it "is not called for a passing result" do
      expect(calls_for(result(passed: true))).to eq([])
    end

    it "is not called for a skipped result" do
      expect(calls_for(result(passed: false, skipped: true))).to eq([])
    end
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

  describe "prerecord" do
    let(:started) { [] }
    let(:tracked) { Henitai::TestFileOutcomes.new(on_started: ->(path) { started << path }) }

    it "reports the file of the test class about to run as started" do
      described_class.new(tracked).prerecord(PrerecordSpecTest, "test_example")

      expect(started).to eq([File.expand_path(__FILE__)])
    end

    it "falls back to the test method's source file for an anonymous class" do
      klass = Class.new { define_method(:test_fallback) { nil } }

      described_class.new(tracked).prerecord(klass, "test_fallback")

      expect(started).to eq([File.expand_path(__FILE__)])
    end

    it "reports nothing when neither the class nor the method has a file" do
      described_class.new(tracked).prerecord(Class.new, "to_s")

      expect(started).to be_empty
    end
  end
end
