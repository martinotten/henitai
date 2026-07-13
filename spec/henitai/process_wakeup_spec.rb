# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ProcessWakeup do
  # USR2 is unused by the test runner, so trapping it here is safe and is
  # always restored by #close in the after hook.
  let(:signal_name) { "USR2" }

  def with_wakeup
    wakeup = described_class.new(signal_name:)
    yield wakeup
  ensure
    wakeup&.close
  end

  describe "#wait" do
    it "returns the ready reader once #signal has written to the pipe" do
      with_wakeup do |wakeup|
        wakeup.signal

        readable, = wakeup.wait(0)

        expect(readable).to be_a(Array).and(be_one)
      end
    end

    it "returns nil when no signal arrives before the timeout" do
      with_wakeup do |wakeup|
        expect(wakeup.wait(0)).to be_nil
      end
    end
  end

  describe "#drain" do
    it "consumes pending bytes so the pipe is no longer readable" do
      with_wakeup do |wakeup|
        wakeup.signal
        wakeup.drain

        expect(wakeup.wait(0)).to be_nil
      end
    end

    it "is a no-op (does not raise) when the pipe is empty" do
      with_wakeup do |wakeup|
        expect { wakeup.drain }.not_to raise_error
      end
    end
  end

  describe "#install" do
    it "traps CHLD by default" do
      allow(Signal).to receive(:trap).and_return("DEFAULT")
      wakeup = described_class.new

      wakeup.install

      expect(Signal).to have_received(:trap).with("CHLD")
    ensure
      wakeup&.close
    end

    it "installs a handler that wakes the pipe when the signal is delivered" do
      previous = Signal.trap(signal_name, "DEFAULT")
      with_wakeup do |wakeup|
        wakeup.install
        Process.kill(signal_name, Process.pid)

        expect(wakeup.wait(1)).not_to be_nil
      end
    ensure
      Signal.trap(signal_name, previous)
    end

    it "returns self so callers can chain" do
      with_wakeup do |wakeup|
        expect(wakeup.install).to be(wakeup)
      end
    end
  end

  describe "#close" do
    it "restores the handler that was installed before #install" do
      sentinel = proc {}
      previous = Signal.trap(signal_name, sentinel)

      wakeup = described_class.new(signal_name:)
      wakeup.install
      wakeup.close

      # Re-trapping returns the handler currently in place; #close must have
      # restored the sentinel rather than leaving the wakeup handler active.
      expect(Signal.trap(signal_name, "DEFAULT")).to be(sentinel)
    ensure
      Signal.trap(signal_name, previous)
    end

    it "is safe to call twice" do
      wakeup = described_class.new(signal_name:)

      wakeup.close
      expect { wakeup.close }.not_to raise_error
    end

    it "does not restore a handler when none was installed" do
      allow(Signal).to receive(:trap)
      wakeup = described_class.new(signal_name:)

      wakeup.close

      expect(Signal).not_to have_received(:trap)
    end
  end
end
