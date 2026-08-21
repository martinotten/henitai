# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ProcessLiveness do
  def raising(error) = ->(_signal, _pid) { raise error }

  describe ".alive?" do
    it "reports the current process as alive" do
      expect(described_class.alive?(Process.pid)).to be(true)
    end

    it "reports a process that no longer exists as dead" do
      expect(described_class.alive?(4_242, kill: raising(Errno::ESRCH))).to be(false)
    end

    # A process owned by another user is running -- we simply may not signal
    # it. Treating EPERM as dead would let the watchdog kill live children and
    # would make the lock's contention diagnostics claim a running owner is
    # gone.
    it "treats a process we may not signal as alive" do
      expect(described_class.alive?(4_242, kill: raising(Errno::EPERM))).to be(true)
    end

    it "treats an unexpected signalling error as alive rather than guessing" do
      expect(described_class.alive?(4_242, kill: raising(StandardError))).to be(true)
    end

    it "reports a non-integer pid as dead" do
      expect(described_class.alive?("unknown")).to be(false)
    end

    it "reports a nil pid as dead" do
      expect(described_class.alive?(nil)).to be(false)
    end

    it "signals zero rather than a real signal" do
      calls = []
      described_class.alive?(4_242, kill: ->(signal, pid) { calls << [signal, pid] })

      expect(calls).to eq([[0, 4_242]])
    end

    # The reason KILL is captured at load time. A mutant child runs the host
    # project's own suite; a spec in that suite stubbing Process.kill to raise
    # ESRCH previously made this answer "dead" for a live parent, and
    # OrphanWatchdog exited the child on the strength of it. Observed as a
    # spurious CompileError on henitai's own dogfood run.
    it "is not fooled by a stubbed Process.kill" do
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

      expect(described_class.alive?(Process.pid)).to be(true)
    end
  end
end
