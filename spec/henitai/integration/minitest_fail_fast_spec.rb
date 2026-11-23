# frozen_string_literal: true

require "minitest"
require "spec_helper"
require "henitai/integration/minitest_fail_fast"

RSpec.describe Henitai::Integration::MinitestFailFast do
  # A real Minitest::Test subclass registers itself with Minitest; it is
  # unregistered again so no other example's Minitest.run picks it up.
  let(:suite) do
    Class.new(Minitest::Test) do
      def test_one = nil
      def test_two = nil
    end
  end

  # runnable_methods shuffles with Minitest.seed, which is unset outside a run.
  around do |example|
    original = Minitest.seed
    Minitest.seed = 0
    example.run
  ensure
    Minitest.seed = original
    Minitest::Runnable.runnables.delete(suite)
    described_class.disarm!
  end

  it "leaves a suite's test methods alone while no failure was reported" do
    described_class.arm!

    expect(suite.runnable_methods).to contain_exactly("test_one", "test_two")
  end

  it "reports no test methods for a suite that starts after the stop" do
    described_class.arm!
    described_class.stop!

    expect(suite.runnable_methods).to eq([])
  end

  it "runs none of a stopped suite's tests" do
    described_class.arm!
    described_class.stop!
    reporter = Minitest::StatisticsReporter.new(StringIO.new)

    suite.run(reporter, {})

    expect(reporter.count).to eq(0)
  end

  it "forgets the stop when disarmed" do
    described_class.arm!
    described_class.stop!
    described_class.disarm!

    expect(suite.runnable_methods.size).to eq(2)
  end

  it "starts every armed run unstopped" do
    described_class.arm!
    described_class.stop!
    described_class.arm!

    expect(described_class.stopped?).to be(false)
  end
end
