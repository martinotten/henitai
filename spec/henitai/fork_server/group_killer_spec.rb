# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ForkServer::GroupKiller, :aggregate_failures do
  before { allow(Process).to receive(:kill) }

  describe ".kill" do
    it "signals the process group, with SIGKILL by default" do
      described_class.kill(42)

      expect(Process).to have_received(:kill).with(:SIGKILL, -42).once
    end

    it "signals the process itself while it has not become a group leader yet" do
      allow(Process).to receive(:kill).with(:SIGTERM, -42).and_raise(Errno::ESRCH)

      described_class.kill(42, :SIGTERM)

      expect(Process).to have_received(:kill).with(:SIGTERM, 42).once
    end

    it "leaves the pid alone when only stragglers of its group were wanted" do
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

      described_class.kill(42, leader: false)

      expect(Process).not_to have_received(:kill).with(:SIGKILL, 42)
    end

    it "ignores a process it may not signal" do
      allow(Process).to receive(:kill).and_raise(Errno::EPERM)

      expect { described_class.kill(42) }.not_to raise_error
      expect(Process).to have_received(:kill).once
    end

    it "tolerates a process that is gone altogether" do
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

      expect { described_class.kill(42) }.not_to raise_error
    end
  end

  describe ".alive?" do
    it "is true while the group has members" do
      expect(described_class.alive?(42)).to be(true)
      expect(Process).to have_received(:kill).with(0, -42)
    end

    it "is true for a process that leads no group yet" do
      allow(Process).to receive(:kill).with(0, -42).and_raise(Errno::ESRCH)

      expect(described_class.alive?(42)).to be(true)
      expect(Process).to have_received(:kill).with(0, 42)
    end

    it "is false once neither group nor process exists" do
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

      expect(described_class.alive?(42)).to be(false)
    end

    it "does not probe the pid itself when only the group counts" do
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

      expect(described_class.alive?(42, leader: false)).to be(false)
      expect(Process).not_to have_received(:kill).with(0, 42)
    end

    it "counts a group or process it may not signal as alive" do
      allow(Process).to receive(:kill).with(0, -42).and_raise(Errno::EPERM)

      expect(described_class.alive?(42)).to be(true)

      allow(Process).to receive(:kill).with(0, -42).and_raise(Errno::ESRCH)
      allow(Process).to receive(:kill).with(0, 42).and_raise(Errno::EPERM)

      expect(described_class.alive?(42)).to be(true)
    end
  end
end
