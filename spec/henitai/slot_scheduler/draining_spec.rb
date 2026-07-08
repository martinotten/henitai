# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SlotScheduler::Draining do
  def build_slot(slot_id:, pid:, draining: false, forced_outcome: nil, **opts)
    Henitai::SlotScheduler::Slot.new(
      slot_id, build_mutant, pid, opts.fetch(:started_at, 0.0), opts.fetch(:timeout, 5.0),
      {}, 0, draining, opts[:term_sent_at], forced_outcome, 0
    )
  end

  def build_mutant
    subject = Struct.new(:expression).new("Foo#bar")
    Struct.new(:id, :subject, :status).new("m", subject, :pending)
  end

  def build_scheduler(now:, wait2_results: {})
    runtime = instance_double(Henitai::ProcessWorkerRunner::Runtime, clock_gettime: now)
    allow(runtime).to receive(:wait2) do |pid, _flags|
      wait2_results.fetch(pid, [nil, nil])
    end
    host = Struct.new(:worker_count, :runtime, :wakeup) do
      def shutdown_requested? = false
    end.new(1, runtime, nil)
    integration = instance_double(Henitai::Integration::Rspec)
    Henitai::SlotScheduler.new(integration: integration, config: nil, progress_reporter: nil, options: {}, host: host)
  end

  def inject_slot(scheduler, slot)
    scheduler.send(:slots)[slot.slot_id] = slot
    scheduler.send(:pid_to_slot)[slot.pid] = slot.slot_id
  end

  describe "#check_timeouts" do
    it "skips slots that are already draining, leaving their forced_outcome untouched" do
      scheduler = build_scheduler(now: 100.0)
      draining_slot = build_slot(slot_id: 0, pid: 10, started_at: 0.0, timeout: 1.0, draining: true,
                                 forced_outcome: :interrupted)
      inject_slot(scheduler, draining_slot)

      scheduler.check_timeouts

      expect(draining_slot.forced_outcome).to eq(:interrupted)
    end

    it "does not touch a slot exactly one tick before its deadline" do
      scheduler = build_scheduler(now: 4.999)
      slot = build_slot(slot_id: 0, pid: 10, started_at: 0.0, timeout: 5.0)
      inject_slot(scheduler, slot)

      scheduler.check_timeouts

      expect(slot.draining).to be(false)
    end

    it "marks a slot well past its deadline as draining", :aggregate_failures do
      scheduler = build_scheduler(now: 10.0, wait2_results: { 10 => [nil, nil] })
      slot = build_slot(slot_id: 0, pid: 10, started_at: 0.0, timeout: 5.0)
      inject_slot(scheduler, slot)

      scheduler.check_timeouts

      expect(slot.draining).to be(true)
      expect(slot.forced_outcome).to eq(:timeout)
    end

    it "marks a slot due exactly at its deadline as draining", :aggregate_failures do
      scheduler = build_scheduler(now: 5.0, wait2_results: { 10 => [nil, nil] })
      slot = build_slot(slot_id: 0, pid: 10, started_at: 0.0, timeout: 5.0)
      inject_slot(scheduler, slot)

      scheduler.check_timeouts

      expect(slot.draining).to be(true)
      expect(slot.forced_outcome).to eq(:timeout)
    end

    it "completes the slot instead of marking it draining when a targeted reap finds it already exited",
       :aggregate_failures do
      scheduler = build_scheduler(now: 5.0, wait2_results: { 10 => [10, instance_double(Process::Status)] })
      slot = build_slot(slot_id: 0, pid: 10, started_at: 0.0, timeout: 5.0)
      inject_slot(scheduler, slot)
      allow(scheduler.send(:integration)).to receive(:build_result).and_return(
        instance_double(Henitai::ScenarioExecutionResult, survived?: false, status: :killed)
      )

      scheduler.check_timeouts

      expect(slot.draining).to be(false)
      expect(scheduler.send(:slots)).to be_empty
    end
  end

  describe "#draining_slots?" do
    it "is false when no slot is draining" do
      scheduler = build_scheduler(now: 0.0)
      inject_slot(scheduler, build_slot(slot_id: 0, pid: 10, draining: false))

      expect(scheduler.draining_slots?).to be(false)
    end

    it "is true when at least one slot is draining" do
      scheduler = build_scheduler(now: 0.0)
      inject_slot(scheduler, build_slot(slot_id: 0, pid: 10, draining: false))
      inject_slot(scheduler, build_slot(slot_id: 1, pid: 11, draining: true))

      expect(scheduler.draining_slots?).to be(true)
    end
  end

  describe "#interrupt_active_slots" do
    it "marks every non-draining slot as interrupted", :aggregate_failures do
      scheduler = build_scheduler(now: 0.0)
      slot = build_slot(slot_id: 0, pid: 10, draining: false)
      inject_slot(scheduler, slot)

      scheduler.interrupt_active_slots

      expect(slot.draining).to be(true)
      expect(slot.forced_outcome).to eq(:interrupted)
    end

    it "leaves an already-draining slot's forced_outcome untouched" do
      scheduler = build_scheduler(now: 0.0)
      slot = build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :timeout)
      inject_slot(scheduler, slot)

      scheduler.interrupt_active_slots

      expect(slot.forced_outcome).to eq(:timeout)
    end
  end

  describe "#draining_slots (private)" do
    it "selects only the slots currently draining" do
      scheduler = build_scheduler(now: 0.0)
      draining_slot = build_slot(slot_id: 0, pid: 10, draining: true)
      live_slot = build_slot(slot_id: 1, pid: 11, draining: false)
      inject_slot(scheduler, draining_slot)
      inject_slot(scheduler, live_slot)

      result = scheduler.send(:draining_slots)

      expect(result).to eq({ 0 => draining_slot })
    end
  end
end
