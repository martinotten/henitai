# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::TimeoutCalibrator do
  def build_calibrator(durations, multiplier: 3.0)
    described_class.new(timing_source: -> { durations }, multiplier:)
  end

  it "returns multiplier times the summed durations of the selected tests" do
    calibrator = build_calibrator(
      {
        "spec/a_spec.rb" => 1.0,
        "spec/b_spec.rb" => 2.0,
        "spec/unrelated_spec.rb" => 50.0
      }
    )

    expect(calibrator.timeout_for(%w[spec/a_spec.rb spec/b_spec.rb])).to eq(9.0)
  end

  it "clamps the result to the floor for near-instant baselines" do
    calibrator = build_calibrator({ "spec/a_spec.rb" => 0.01 })

    expect(calibrator.timeout_for(%w[spec/a_spec.rb])).to eq(
      described_class::FLOOR_SECONDS
    )
  end

  it "returns nil when any selected test has no recorded duration" do
    calibrator = build_calibrator({ "spec/a_spec.rb" => 1.0 })

    expect(calibrator.timeout_for(%w[spec/a_spec.rb spec/missing_spec.rb])).to be_nil
  end

  it "returns nil when no timing data exists at all" do
    calibrator = build_calibrator({})

    expect(calibrator.timeout_for(%w[spec/a_spec.rb])).to be_nil
  end

  it "returns nil for an empty test selection" do
    calibrator = build_calibrator({ "spec/a_spec.rb" => 1.0 })

    expect(calibrator.timeout_for([])).to be_nil
  end

  it "matches absolute test paths against relative timing keys" do
    calibrator = build_calibrator({ "spec/a_spec.rb" => 1.0 })

    expect(calibrator.timeout_for([File.expand_path("spec/a_spec.rb")])).to eq(3.0)
  end

  it "matches ./-prefixed timing keys against plain relative paths" do
    calibrator = build_calibrator({ "./spec/a_spec.rb" => 1.0 })

    expect(calibrator.timeout_for(%w[spec/a_spec.rb])).to eq(3.0)
  end

  it "resolves the timing source only once" do
    calls = 0
    calibrator = described_class.new(
      timing_source: lambda {
        calls += 1
        { "spec/a_spec.rb" => 1.0 }
      },
      multiplier: 3.0
    )

    calibrator.timeout_for(%w[spec/a_spec.rb])
    calibrator.timeout_for(%w[spec/a_spec.rb])

    expect(calls).to eq(1)
  end
end
