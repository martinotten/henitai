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

  it "treats empty output as a run with no summary" do
    expect(described_class.none_ran?(nil)).to be(false)
  end
end
