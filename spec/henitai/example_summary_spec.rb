# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ExampleSummary do
  it "detects a run that found no examples" do
    expect(described_class.none_ran?("No examples found.\n0 examples, 0 failures\n")).to be(true)
  end

  it "detects a zero-example summary" do
    expect(described_class.none_ran?("\n0 examples, 0 failures\n")).to be(true)
  end

  it "does not count a run with examples" do
    expect(described_class.none_ran?("10 examples, 0 failures\n")).to be(false)
  end

  it "ignores texts quoted, indented, in failure output" do
    output = "  expect(x).to eq(\"0 examples, 0 failures\")\n  # No examples found.\n14 examples, 2 failures\n"

    expect(described_class.none_ran?(output)).to be(false)
  end

  it "judges by the last summary line" do
    expect([described_class.none_ran?("0 examples, 0 failures\n3 examples, 1 failure\n"),
            described_class.none_ran?("3 examples, 1 failure\n0 examples, 0 failures\n")]).to eq([false, true])
  end

  it "lets the last summary line override an unindented no-examples line" do
    output = "No examples found.\n14 examples, 2 failures\n"

    expect(described_class.none_ran?(output)).to be(false)
  end

  it "detects a Minitest run that executed no tests" do
    output = "Finished in 0.001s\n0 runs, 0 assertions, 0 failures, 0 errors, 0 skips\n"

    expect(described_class.none_ran?(output)).to be(true)
  end

  it "does not count a Minitest run with tests" do
    expect(described_class.none_ran?("3 runs, 4 assertions, 0 failures, 0 errors, 0 skips\n")).to be(false)
  end

  it "judges a Minitest run by its last summary line" do
    output = [
      "0 runs, 0 assertions, 0 failures, 0 errors, 0 skips",
      "2 runs, 2 assertions, 0 failures, 0 errors, 0 skips"
    ].join("\n")

    expect(described_class.none_ran?(output)).to be(false)
  end

  it "treats empty output as a run with no summary" do
    expect(described_class.none_ran?(nil)).to be(false)
  end
end
