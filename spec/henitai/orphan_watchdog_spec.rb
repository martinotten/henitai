# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::OrphanWatchdog do
  let(:parent_pid_value) { 100 }
  let(:reparented_pid_value) { 1 }

  # Every collaborator is injected, so the decision logic is testable without
  # forking anything. The real fork path is covered in
  # orphan_watchdog_process_spec.rb.
  def build(parent_pid: 100, ppid: 100, alive: true, &on_orphan)
    liveness = Class.new do
      define_method(:alive?) { |_pid| alive }
    end.new

    described_class.new(
      parent_pid:,
      interval: 0.0,
      liveness:,
      ppid: -> { ppid },
      on_orphan: on_orphan || -> {},
      sleeper: ->(_seconds) {}
    )
  end

  describe "#orphaned?" do
    it "is false while the parent is still our parent and alive" do
      expect(build.orphaned?).to be(false)
    end

    # The definitive arm: reparenting to init cannot be faked by pid reuse.
    it "is true once we have been reparented" do
      expect(build(parent_pid: 100, ppid: 1).orphaned?).to be(true)
    end

    # The second arm, for a parent that lingers as a zombie so ppid still
    # matches.
    it "is true once the parent process is gone" do
      expect(build(alive: false).orphaned?).to be(true)
    end
  end

  describe "#run" do
    it "invokes the orphan handler once reparented" do
      fired = false
      build(ppid: 1) { fired = true }.run

      expect(fired).to be(true)
    end

    it "invokes the orphan handler once the parent process is gone" do
      fired = false
      build(alive: false) { fired = true }.run

      expect(fired).to be(true)
    end

    it "hands over exactly once rather than looping after it has acted" do
      fires = 0
      build(ppid: 1) { fires += 1 }.run

      expect(fires).to eq(1)
    end

    # Checked before the first sleep, so a child forked from an already-dead
    # parent does not linger for a whole interval.
    it "does not sleep when already orphaned" do
      expect(sleeps_before_acting(healthy_polls: 0)).to be_empty
    end

    it "sleeps for the configured interval while the parent is healthy" do
      expect(sleeps_before_acting(healthy_polls: 2)).to eq([0.25, 0.25])
    end
  end

  # Runs the watchdog against a parent that looks healthy for the first
  # `healthy_polls` checks and reparented afterwards, returning the intervals
  # it slept for. The post-healthy pid must differ from parent_pid, or #run
  # never terminates.
  def sleeps_before_acting(healthy_polls:)
    slept = []
    checks = 0
    described_class.new(
      parent_pid: parent_pid_value,
      interval: 0.25,
      liveness: Class.new { def alive?(_pid) = true }.new,
      ppid: -> { (checks += 1) <= healthy_polls ? parent_pid_value : reparented_pid_value },
      on_orphan: -> {},
      sleeper: ->(seconds) { slept << seconds }
    ).run
    slept
  end

  describe ".enabled?" do
    it "is enabled when the environment says nothing" do
      expect(described_class.enabled?({})).to be(true)
    end

    # Opt-OUT, unlike HENITAI_DEBUG_CHILD which is opt-in: a watchdog that is
    # off by default would never run for the users it exists to protect.
    it "is disabled only by an explicit zero" do
      expect(described_class.enabled?({ "HENITAI_CHILD_WATCHDOG" => "0" })).to be(false)
    end

    it "stays enabled for any other value" do
      expect(described_class.enabled?({ "HENITAI_CHILD_WATCHDOG" => "1" })).to be(true)
    end
  end

  describe ".poll_interval" do
    it "defaults when unset" do
      expect(described_class.poll_interval({})).to eq(described_class::DEFAULT_INTERVAL)
    end

    it "reads a float from the environment" do
      expect(described_class.poll_interval({ "HENITAI_CHILD_WATCHDOG_INTERVAL" => "0.05" })).to eq(0.05)
    end

    it "falls back to the default for an unparseable value" do
      expect(described_class.poll_interval({ "HENITAI_CHILD_WATCHDOG_INTERVAL" => "soon" }))
        .to eq(described_class::DEFAULT_INTERVAL)
    end

    it "falls back to the default for a non-positive value" do
      expect(described_class.poll_interval({ "HENITAI_CHILD_WATCHDOG_INTERVAL" => "0" }))
        .to eq(described_class::DEFAULT_INTERVAL)
    end
  end

  # DANGER: .start builds a watchdog with the real on_orphan, which calls
  # Kernel.exit!. A live watchdog thread must never run inside the test
  # process: if this process is ever reparented -- which happens routinely when
  # a CI shell or wrapper exits -- the thread decides it has been orphaned and
  # takes the whole RSpec run down with exit status 2, producing no failure
  # output and no summary at all. Thread#kill is asynchronous and cannot be
  # relied on to win that race, so Thread.new is stubbed instead and the body
  # never executes here. The real thread is exercised by
  # orphan_watchdog_process_spec.rb, in a child process where exiting is the
  # intended outcome.
  describe ".start" do
    let(:thread) { instance_double(Thread) }

    before { allow(Thread).to receive(:new).and_return(thread) }

    it "does not start a thread when disabled" do
      expect(described_class.start(parent_pid: 4_242, env: { "HENITAI_CHILD_WATCHDOG" => "0" }))
        .to be_nil
    end

    it "starts no thread at all when disabled" do
      described_class.start(parent_pid: 4_242, env: { "HENITAI_CHILD_WATCHDOG" => "0" })

      expect(Thread).not_to have_received(:new)
    end

    it "returns the started thread when enabled" do
      expect(described_class.start(parent_pid: 4_242, env: {})).to be(thread)
    end
  end
end
