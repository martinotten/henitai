# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::FlakyRetryDecision do
  let(:flaky_tests) { Henitai::FlakyTestRegistry.new(["/app/spec/flaky_spec.rb"]) }
  let(:decision) { described_class.new(flaky_tests: flaky_tests, max_retries: 3) }

  it "never retries a survived verdict" do
    expect(decision.retry?(status: :survived, killing_tests: [], attempts: 0)).to be(false)
  end

  it "retries a kill whose killing tests are all known flaky" do
    expect(
      decision.retry?(status: :killed, killing_tests: ["/app/spec/flaky_spec.rb"], attempts: 0)
    ).to be(true)
  end

  it "does not retry a kill when any killing test is stable" do
    expect(
      decision.retry?(
        status: :killed,
        killing_tests: ["/app/spec/flaky_spec.rb", "/app/spec/stable_spec.rb"],
        attempts: 0
      )
    ).to be(false)
  end

  it "does not retry a kill without killing tests" do
    expect(decision.retry?(status: :killed, killing_tests: [], attempts: 0)).to be(false)
  end

  it "requires every failed file, not just one, to be flaky" do
    expect(
      decision.retry?(
        status: :killed,
        killing_tests: ["/app/spec/stable_spec.rb", "/app/spec/flaky_spec.rb"],
        attempts: 0
      )
    ).to be(false)
  end

  it "stops retrying once the retry budget is spent" do
    expect(
      decision.retry?(status: :killed, killing_tests: ["/app/spec/flaky_spec.rb"], attempts: 3)
    ).to be(false)
  end

  it "does not retry anything when no flaky tests are known" do
    decision = described_class.new(flaky_tests: Henitai::FlakyTestRegistry.new([]), max_retries: 3)

    expect(
      decision.retry?(status: :killed, killing_tests: ["/app/spec/flaky_spec.rb"], attempts: 0)
    ).to be(false)
  end
end
