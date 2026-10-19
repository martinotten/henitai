# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::TimeoutCeiling do
  let(:warnings) { [] }
  let(:ceiling) { described_class.new(ceiling: 30.0, warner: ->(message) { warnings << message }) }
  let(:floor) { Henitai::TimeoutCalibrator::FLOOR_SECONDS }

  it "returns the calibrated timeout when it fits under the ceiling" do
    expect(ceiling.cap(20.0, 10.0)).to eq(20.0)
  end

  it "does not warn when the calibrated timeout fits under the ceiling" do
    ceiling.cap(20.0, 10.0)

    expect(warnings).to be_empty
  end

  it "caps a calibrated timeout at the ceiling when the baseline fits" do
    expect(ceiling.cap(45.0, 10.0)).to eq(30.0)
  end

  it "never caps the timeout below the measured baseline" do
    expect(ceiling.cap(60.0, 29.0)).to eq(29.0 + floor)
  end

  it "does not warn when the baseline fits under the ceiling" do
    ceiling.cap(60.0, 29.0)

    expect(warnings).to be_empty
  end

  it "warns with the baseline, ceiling and effective timeout when the baseline exceeds the ceiling" do
    ceiling.cap(70.0, 35.0)

    expect(warnings).to eq(
      ["henitai: measured test baseline of 35.0s exceeds max_timeout (30.0s); using 37.0s instead"]
    )
  end

  it "warns only once across repeated calls" do
    ceiling.cap(70.0, 35.0)
    ceiling.cap(70.0, 36.0)

    expect(warnings.size).to eq(1)
  end
end
