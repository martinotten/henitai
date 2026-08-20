# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ProcessLiveness do
  describe ".alive?" do
    it "reports the current process as alive" do
      expect(described_class.alive?(Process.pid)).to be(true)
    end

    it "reports a process that no longer exists as dead" do
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

      expect(described_class.alive?(4_242)).to be(false)
    end

    # A process owned by another user is running -- we simply may not signal
    # it. Treating EPERM as dead would let the watchdog kill live children and
    # would make the lock's contention diagnostics claim a running owner is
    # gone.
    it "treats a process we may not signal as alive" do
      allow(Process).to receive(:kill).and_raise(Errno::EPERM)

      expect(described_class.alive?(4_242)).to be(true)
    end

    it "treats an unexpected signalling error as alive rather than guessing" do
      allow(Process).to receive(:kill).and_raise(StandardError)

      expect(described_class.alive?(4_242)).to be(true)
    end

    it "reports a non-integer pid as dead" do
      expect(described_class.alive?("unknown")).to be(false)
    end

    it "reports a nil pid as dead" do
      expect(described_class.alive?(nil)).to be(false)
    end

    it "signals zero rather than a real signal" do
      allow(Process).to receive(:kill)

      described_class.alive?(4_242)

      expect(Process).to have_received(:kill).with(0, 4_242)
    end
  end
end
