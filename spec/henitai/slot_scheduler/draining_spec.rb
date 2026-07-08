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

  def build_runtime(now:, wait2_results:, wait_results:)
    runtime = instance_double(Henitai::ProcessWorkerRunner::Runtime, clock_gettime: now)
    allow(runtime).to receive(:wait2) { |pid, _flags| wait2_results.fetch(pid, [nil, nil]) }
    allow(runtime).to receive(:wait) { |pid| wait_results.fetch(pid, pid) }
    allow(runtime).to receive(:kill)
    runtime
  end

  def build_scheduler(now:, wait2_results: {}, **opts)
    runtime = build_runtime(now: now, wait2_results: wait2_results, wait_results: opts[:wait_results] || {})
    host = Struct.new(:worker_count, :runtime, :wakeup) do
      def shutdown_requested? = false
    end.new(1, runtime, opts[:wakeup])
    Henitai::SlotScheduler.new(
      integration: opts[:integration] || instance_double(Henitai::Integration::Rspec),
      config: nil, progress_reporter: opts[:progress_reporter], options: {}, host: host
    )
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

  describe "#drain_draining_slots" do
    it "does nothing when there are no draining slots" do
      scheduler = build_scheduler(now: 0.0)
      inject_slot(scheduler, build_slot(slot_id: 0, pid: 10, draining: false))

      scheduler.drain_draining_slots

      expect(scheduler.send(:runtime)).not_to have_received(:kill)
    end

    it "stops after pruning when every draining slot already exited naturally", :aggregate_failures do
      status = instance_double(Process::Status, exited?: true)
      scheduler = build_scheduler(now: 0.0, wait2_results: { 10 => [10, status] })
      allow(scheduler.send(:integration)).to receive(:build_result).and_return(
        instance_double(Henitai::ScenarioExecutionResult, survived?: false, status: :killed)
      )
      inject_slot(scheduler, build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :timeout))

      scheduler.drain_draining_slots

      expect(scheduler.send(:runtime)).not_to have_received(:kill)
      expect(scheduler.send(:slots)).to be_empty
    end

    it "broadcasts SIGTERM then SIGKILL and reaps the survivors", :aggregate_failures do
      wakeup = instance_double(Henitai::ProcessWakeup, wait: nil, drain: nil)
      scheduler = build_scheduler(now: 0.0, wakeup: wakeup)
      allow(scheduler.send(:integration)).to receive(:build_result).and_return(
        instance_double(Henitai::ScenarioExecutionResult, survived?: false, status: :timeout)
      )
      inject_slot(scheduler, build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :timeout))
      calls = []
      runtime = scheduler.send(:runtime)
      allow(runtime).to receive(:kill) { |signal, pid| calls << [signal, pid] }

      scheduler.drain_draining_slots

      expect(calls).to eq([[:SIGTERM, -10], [:SIGKILL, -10]])
      expect(wakeup).to have_received(:wait).with(Henitai::SlotScheduler::PROCESS_DRAIN_WINDOW)
      expect(scheduler.send(:slots)).to be_empty
    end
  end

  describe "#prune_raced_draining_slots" do
    it "removes and completes a slot whose pid already exited", :aggregate_failures do
      status = instance_double(Process::Status, exited?: true)
      scheduler = build_scheduler(now: 0.0, wait2_results: { 10 => [10, status] })
      allow(scheduler.send(:integration)).to receive(:build_result).and_return(
        instance_double(Henitai::ScenarioExecutionResult, survived?: false, status: :killed)
      )
      slot = build_slot(slot_id: 0, pid: 10, draining: true)
      inject_slot(scheduler, slot)
      draining = { 0 => slot }

      scheduler.send(:prune_raced_draining_slots, draining)

      expect(draining).to be_empty
      expect(scheduler.send(:slots)).to be_empty
    end

    it "keeps a slot whose pid has not exited yet" do
      scheduler = build_scheduler(now: 0.0)
      slot = build_slot(slot_id: 0, pid: 10, draining: true)
      inject_slot(scheduler, slot)
      draining = { 0 => slot }

      scheduler.send(:prune_raced_draining_slots, draining)

      expect(draining).to eq({ 0 => slot })
    end
  end

  describe "#wait_for_drain_window" do
    it "waits then drains the wakeup when present", :aggregate_failures do
      wakeup = instance_double(Henitai::ProcessWakeup, wait: nil, drain: nil)
      scheduler = build_scheduler(now: 0.0, wakeup: wakeup)

      scheduler.send(:wait_for_drain_window)

      expect(wakeup).to have_received(:wait).with(Henitai::SlotScheduler::PROCESS_DRAIN_WINDOW)
      expect(wakeup).to have_received(:drain)
    end

    it "does not raise when there is no wakeup" do
      scheduler = build_scheduler(now: 0.0, wakeup: nil)

      expect { scheduler.send(:wait_for_drain_window) }.not_to raise_error
    end
  end

  describe "#signal_draining_slots" do
    it "sends SIGKILL to every draining slot's process group", :aggregate_failures do
      scheduler = build_scheduler(now: 0.0)
      slot_a = build_slot(slot_id: 0, pid: 10, draining: true)
      slot_b = build_slot(slot_id: 1, pid: 11, draining: true)

      scheduler.send(:signal_draining_slots, { 0 => slot_a, 1 => slot_b })

      runtime = scheduler.send(:runtime)
      expect(runtime).to have_received(:kill).with(:SIGKILL, -10)
      expect(runtime).to have_received(:kill).with(:SIGKILL, -11)
    end
  end

  describe "#broadcast_term" do
    it "stamps term_sent_at_monotonic and sends SIGTERM to each slot", :aggregate_failures do
      scheduler = build_scheduler(now: 42.0)
      slot = build_slot(slot_id: 0, pid: 10, draining: true)

      scheduler.send(:broadcast_term, { 0 => slot })

      expect(slot.term_sent_at_monotonic).to eq(42.0)
      expect(scheduler.send(:runtime)).to have_received(:kill).with(:SIGTERM, -10)
    end
  end

  describe "#reap_and_finalize_slot" do
    it "skips the blocking reap when the targeted WNOHANG already found an exit status" do
      status = instance_double(Process::Status, exited?: true)
      scheduler = build_scheduler(now: 0.0, wait2_results: { 10 => [10, status] })
      allow(scheduler.send(:integration)).to receive(:build_result).and_return(
        instance_double(Henitai::ScenarioExecutionResult, survived?: false, status: :killed)
      )
      slot = build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :timeout)
      inject_slot(scheduler, slot)

      scheduler.send(:reap_and_finalize_slot, slot)

      expect(scheduler.send(:runtime)).not_to have_received(:wait)
    end

    it "performs a blocking reap when the targeted WNOHANG found nothing" do
      scheduler = build_scheduler(now: 0.0, wait2_results: { 10 => [nil, nil] })
      allow(scheduler.send(:integration)).to receive(:build_result).and_return(
        instance_double(Henitai::ScenarioExecutionResult, survived?: false, status: :killed)
      )
      slot = build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :timeout)
      inject_slot(scheduler, slot)

      scheduler.send(:reap_and_finalize_slot, slot)

      expect(scheduler.send(:runtime)).to have_received(:wait).with(10)
    end

    it "removes the slot from both tables and reports it to SchedulerDiagnostics", :aggregate_failures do
      scheduler = build_scheduler(now: 0.0, wait2_results: { 10 => [nil, nil] })
      allow(scheduler.send(:integration)).to receive(:build_result).and_return(
        instance_double(Henitai::ScenarioExecutionResult, survived?: false, status: :killed)
      )
      allow(Henitai::Integration::SchedulerDiagnostics).to receive(:child_ended)
      slot = build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :timeout)
      inject_slot(scheduler, slot)

      scheduler.send(:reap_and_finalize_slot, slot)

      expect(scheduler.send(:slots)).to be_empty
      expect(scheduler.send(:pid_to_slot)).to be_empty
      expect(Henitai::Integration::SchedulerDiagnostics).to have_received(:child_ended).with(10)
    end

    it "records no result for an interrupted slot" do
      scheduler = build_scheduler(now: 0.0, wait2_results: { 10 => [nil, nil] })
      slot = build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :interrupted)
      inject_slot(scheduler, slot)

      scheduler.send(:reap_and_finalize_slot, slot)

      expect(scheduler.results).to be_empty
    end

    it "records a result for a non-interrupted slot" do
      scheduler = build_scheduler(now: 0.0, wait2_results: { 10 => [nil, nil] })
      killed = instance_double(Henitai::ScenarioExecutionResult, survived?: false, status: :killed)
      allow(scheduler.send(:integration)).to receive(:build_result).and_return(killed)
      slot = build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :timeout)
      inject_slot(scheduler, slot)

      scheduler.send(:reap_and_finalize_slot, slot)

      expect(scheduler.results).to eq([killed])
    end

    it "records a result for a forced_outcome that sorts before :interrupted" do
      scheduler = build_scheduler(now: 0.0, wait2_results: { 10 => [nil, nil] })
      killed = instance_double(Henitai::ScenarioExecutionResult, survived?: false, status: :killed)
      allow(scheduler.send(:integration)).to receive(:build_result).and_return(killed)
      slot = build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :aborted)
      inject_slot(scheduler, slot)

      scheduler.send(:reap_and_finalize_slot, slot)

      expect(scheduler.results).to eq([killed])
    end
  end

  describe "#record_drain_result" do
    it "sets mutant status, appends the result, and reports progress", :aggregate_failures do
      progress_reporter = instance_double(Henitai::Reporter::Terminal)
      allow(progress_reporter).to receive(:progress)
      scheduler = build_scheduler(now: 0.0, progress_reporter: progress_reporter)
      killed = instance_double(Henitai::ScenarioExecutionResult, status: :killed)
      allow(scheduler.send(:integration)).to receive(:build_result).and_return(killed)
      slot = build_slot(slot_id: 0, pid: 10, forced_outcome: :timeout)

      scheduler.send(:record_drain_result, slot, nil)

      expect(slot.mutant.status).to eq(:killed)
      expect(scheduler.results).to eq([killed])
      expect(progress_reporter).to have_received(:progress).with(slot.mutant, scenario_result: killed)
    end
  end

  describe "#build_drain_result" do
    it "uses the real exit status when it exited before any signal was sent" do
      status = instance_double(Process::Status, exited?: true)
      scheduler = build_scheduler(now: 0.0)
      slot = build_slot(slot_id: 0, pid: 10, forced_outcome: :timeout)
      allow(scheduler.send(:integration)).to receive(:build_result).with(status, slot.log_paths).and_return(:real)

      expect(scheduler.send(:build_drain_result, slot, status)).to eq(:real)
    end

    it "uses the forced outcome when a signal was already sent, even if the status exited" do
      status = instance_double(Process::Status, exited?: true)
      scheduler = build_scheduler(now: 0.0)
      slot = build_slot(slot_id: 0, pid: 10, forced_outcome: :interrupted, term_sent_at: 1.0)
      allow(scheduler.send(:integration)).to receive(:build_result).with(:interrupted, slot.log_paths)
                                                                   .and_return(:forced)

      expect(scheduler.send(:build_drain_result, slot, status)).to eq(:forced)
    end

    it "uses the forced outcome when the status did not exit" do
      status = instance_double(Process::Status, exited?: false)
      scheduler = build_scheduler(now: 0.0)
      slot = build_slot(slot_id: 0, pid: 10, forced_outcome: :interrupted)
      allow(scheduler.send(:integration)).to receive(:build_result).with(:interrupted, slot.log_paths)
                                                                   .and_return(:forced)

      expect(scheduler.send(:build_drain_result, slot, status)).to eq(:forced)
    end

    it "falls back to :timeout when the status did not exit and forced_outcome is nil" do
      status = instance_double(Process::Status, exited?: false)
      scheduler = build_scheduler(now: 0.0)
      slot = build_slot(slot_id: 0, pid: 10, forced_outcome: nil)
      allow(scheduler.send(:integration)).to receive(:build_result).with(:timeout, slot.log_paths).and_return(:fallback)

      expect(scheduler.send(:build_drain_result, slot, status)).to eq(:fallback)
    end

    it "uses the forced outcome when final_status is nil" do
      scheduler = build_scheduler(now: 0.0)
      slot = build_slot(slot_id: 0, pid: 10, forced_outcome: :timeout)
      allow(scheduler.send(:integration)).to receive(:build_result).with(:timeout, slot.log_paths).and_return(:forced)

      expect(scheduler.send(:build_drain_result, slot, nil)).to eq(:forced)
    end
  end
end
