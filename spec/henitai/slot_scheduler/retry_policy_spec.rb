# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SlotScheduler::RetryPolicy do
  subject(:policy) { described_class.new(max_retries: 3) }

  def build_slot(retry_count)
    Henitai::SlotScheduler::Slot.new(1, nil, 12, 0.0, 5.0, nil, retry_count, false, nil, nil, 0)
  end

  let(:survived) { instance_double(Henitai::ScenarioExecutionResult, survived?: true) }
  let(:killed) { instance_double(Henitai::ScenarioExecutionResult, survived?: false) }

  it "is false when shutdown has been requested" do
    expect(policy.retry?(slot: build_slot(0), result: survived, shutdown: true)).to be(false)
  end

  it "is false when the result did not survive" do
    expect(policy.retry?(slot: build_slot(0), result: killed, shutdown: false)).to be(false)
  end

  it "is true when retry_count is one below the max" do
    expect(policy.retry?(slot: build_slot(2), result: survived, shutdown: false)).to be(true)
  end

  it "is false once retry_count reaches the max exactly" do
    expect(policy.retry?(slot: build_slot(3), result: survived, shutdown: false)).to be(false)
  end

  it "is false when retry_count already exceeds the max" do
    expect(policy.retry?(slot: build_slot(4), result: survived, shutdown: false)).to be(false)
  end

  it "coerces a string max_retries to an integer for comparison" do
    policy = described_class.new(max_retries: "3")

    expect(policy.retry?(slot: build_slot(2), result: survived, shutdown: false)).to be(true)
  end

  it "treats a nil max_retries as no retries at all" do
    policy = described_class.new(max_retries: nil)

    expect(policy.retry?(slot: build_slot(0), result: survived, shutdown: false)).to be(false)
  end

  it "does not ask the result whether it survived once shutdown vetoes the retry" do
    # Ordering matters on the shutdown path: a torn-down run must not respawn,
    # and must not depend on the result object still being readable.
    result = instance_double(Henitai::ScenarioExecutionResult, survived?: true)

    policy.retry?(slot: build_slot(0), result: result, shutdown: true)

    expect(result).not_to have_received(:survived?)
  end
end
