# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SuiteBootClock do
  def build_clock(now:, started_at: 100.0)
    described_class.new(started_at:, clock: -> { now })
  end

  it "measures the time from the suite start to the first test start" do
    clock = build_clock(now: 102.5)

    clock.mark_first_test_started

    expect(clock.boot_seconds).to eq(2.5)
  end

  it "keeps the measurement taken at the first test start" do
    now = 102.5
    clock = described_class.new(started_at: 100.0, clock: -> { now })
    clock.mark_first_test_started
    now = 110.0
    clock.mark_first_test_started

    expect(clock.boot_seconds).to eq(2.5)
  end

  it "reports zero before any test has started" do
    expect(build_clock(now: 102.5).boot_seconds).to eq(0.0)
  end

  it "reports zero when no suite start stamp is known" do
    clock = described_class.new(started_at: nil, clock: -> { 102.5 })

    clock.mark_first_test_started

    expect(clock.boot_seconds).to eq(0.0)
  end

  it "clamps a clock that appears to run backwards to zero" do
    clock = build_clock(now: 99.0)

    clock.mark_first_test_started

    expect(clock.boot_seconds).to eq(0.0)
  end

  it "reads the suite start stamp from the environment" do
    clock = described_class.from_env(
      { described_class::STARTED_AT_ENV => "100.5" },
      clock: -> { 103.0 }
    )

    clock.mark_first_test_started

    expect(clock.boot_seconds).to eq(2.5)
  end

  it "treats a malformed environment stamp as unknown" do
    clock = described_class.from_env(
      { described_class::STARTED_AT_ENV => "not-a-time" },
      clock: -> { 103.0 }
    )

    clock.mark_first_test_started

    expect(clock.boot_seconds).to eq(0.0)
  end
end
