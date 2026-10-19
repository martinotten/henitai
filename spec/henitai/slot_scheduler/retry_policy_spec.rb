# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SlotScheduler::RetryPolicy do
  subject(:policy) { described_class.new(max_retries: 3, flaky_tests: flaky_tests) }

  let(:flaky_tests) { Henitai::FlakyTestRegistry.new(["/app/spec/flaky_spec.rb"]) }
  let(:survived) { result(status: :survived) }
  let(:flaky_kill) { result(status: :killed, killing_tests: ["/app/spec/flaky_spec.rb"]) }

  def build_slot(retry_count)
    Henitai::SlotScheduler::Slot.new(1, nil, 12, 0.0, 5.0, nil, retry_count, false, nil, nil, 0)
  end

  def result(status:, killing_tests: [])
    instance_double(Henitai::ScenarioExecutionResult, status:, killing_tests:)
  end

  it "is false when shutdown has been requested" do
    expect(policy.retry?(slot: build_slot(0), result: flaky_kill, shutdown: true)).to be(false)
  end

  it "never retries a survivor" do
    expect(policy.retry?(slot: build_slot(0), result: survived, shutdown: false)).to be(false)
  end

  it "retries a kill whose killing tests are all flaky" do
    expect(policy.retry?(slot: build_slot(2), result: flaky_kill, shutdown: false)).to be(true)
  end

  it "does not retry a kill caused by a test that is not known to be flaky" do
    stable_kill = result(status: :killed, killing_tests: ["/app/spec/stable_spec.rb"])

    expect(policy.retry?(slot: build_slot(0), result: stable_kill, shutdown: false)).to be(false)
  end

  it "does not retry a kill with no killing tests reported" do
    expect(policy.retry?(slot: build_slot(0), result: result(status: :killed), shutdown: false)).to be(false)
  end

  it "is false once retry_count reaches the max exactly" do
    expect(policy.retry?(slot: build_slot(3), result: flaky_kill, shutdown: false)).to be(false)
  end

  it "retries nothing when no flaky set is known" do
    policy = described_class.new(max_retries: 3, flaky_tests: Henitai::FlakyTestRegistry.new([]))

    expect(policy.retry?(slot: build_slot(0), result: flaky_kill, shutdown: false)).to be(false)
  end

  it "coerces a string max_retries to an integer for comparison" do
    policy = described_class.new(max_retries: "3", flaky_tests: flaky_tests)

    expect(policy.retry?(slot: build_slot(2), result: flaky_kill, shutdown: false)).to be(true)
  end

  it "treats a nil max_retries as no retries at all" do
    policy = described_class.new(max_retries: nil, flaky_tests: flaky_tests)

    expect(policy.retry?(slot: build_slot(0), result: flaky_kill, shutdown: false)).to be(false)
  end

  it "does not ask the result for its status once shutdown vetoes the retry" do
    # Ordering matters on the shutdown path: a torn-down run must not respawn,
    # and must not depend on the result object still being readable.
    result = instance_double(Henitai::ScenarioExecutionResult, status: :killed, killing_tests: [])

    policy.retry?(slot: build_slot(0), result: result, shutdown: true)

    expect(result).not_to have_received(:status)
  end
end
