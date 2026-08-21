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

  def build_runtime(now: 0.0, wait2_results: {}, wait_results: {})
    runtime = instance_double(Henitai::ProcessWorkerRunner::Runtime, clock_gettime: now)
    allow(runtime).to receive(:wait2) { |pid, _flags| wait2_results.fetch(pid, [nil, nil]) }
    allow(runtime).to receive(:wait) { |pid| wait_results.fetch(pid, pid) }
    allow(runtime).to receive(:kill)
    runtime
  end

  # An integration whose #build_result always answers with `result`. Examples
  # that care *which* wait status reached it stub the double themselves and
  # pass it in as `integration:` instead.
  def build_integration(result)
    instance_double(Henitai::Integration::Rspec).tap do |integration|
      allow(integration).to receive(:build_result).and_return(result)
    end
  end

  def build_result(status: :killed, survived: false)
    instance_double(Henitai::ScenarioExecutionResult, survived?: survived, status: status)
  end

  # One table per example, injected into the scheduler, so an example can seed
  # mid-drain state and assert through the table's own public interface instead
  # of reaching a private reader on the scheduler.
  let(:slot_table) { Henitai::SlotScheduler::SlotTable.new }

  # `runtime:` and `integration:` are injectable so an example can hold onto
  # the collaborator it asserts against instead of reaching back through the
  # scheduler's private readers.
  def build_host(**opts)
    runtime = opts[:runtime] || build_runtime(
      now: opts.fetch(:now, 0.0),
      wait2_results: opts[:wait2_results] || {},
      wait_results: opts[:wait_results] || {}
    )
    Struct.new(:worker_count, :runtime, :wakeup) do
      def shutdown_requested? = false
    end.new(1, runtime, opts[:wakeup])
  end

  def build_scheduler(**opts)
    Henitai::SlotScheduler.new(
      host: build_host(**opts),
      integration: opts[:integration] || instance_double(Henitai::Integration::Rspec),
      config: opts[:config] || Struct.new(:max_flaky_retries).new(0),
      progress_reporter: opts[:progress_reporter], options: {},
      slot_table: opts[:slot_table] || slot_table
    )
  end

  def inject_slot(_scheduler, slot)
    slot_table.add(slot)
    slot_table.register_pid(slot.pid, slot.slot_id)
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
      scheduler = build_scheduler(
        now: 5.0,
        wait2_results: { 10 => [10, instance_double(Process::Status)] },
        integration: build_integration(build_result)
      )
      slot = build_slot(slot_id: 0, pid: 10, started_at: 0.0, timeout: 5.0)
      inject_slot(scheduler, slot)

      scheduler.check_timeouts

      expect(slot.draining).to be(false)
      expect(slot_table).to be_empty
    end
  end

  describe "#draining_slots?" do
    it "is false when no slot is draining" do
      scheduler = build_scheduler
      inject_slot(scheduler, build_slot(slot_id: 0, pid: 10, draining: false))

      expect(scheduler.draining_slots?).to be(false)
    end

    it "is true when at least one slot is draining" do
      scheduler = build_scheduler
      inject_slot(scheduler, build_slot(slot_id: 0, pid: 10, draining: false))
      inject_slot(scheduler, build_slot(slot_id: 1, pid: 11, draining: true))

      expect(scheduler.draining_slots?).to be(true)
    end
  end

  describe "#interrupt_active_slots" do
    it "marks every non-draining slot as interrupted", :aggregate_failures do
      scheduler = build_scheduler
      slot = build_slot(slot_id: 0, pid: 10, draining: false)
      inject_slot(scheduler, slot)

      scheduler.interrupt_active_slots

      expect(slot.draining).to be(true)
      expect(slot.forced_outcome).to eq(:interrupted)
    end

    it "leaves an already-draining slot's forced_outcome untouched" do
      scheduler = build_scheduler
      slot = build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :timeout)
      inject_slot(scheduler, slot)

      scheduler.interrupt_active_slots

      expect(slot.forced_outcome).to eq(:timeout)
    end
  end

  describe "#draining_slots (private)" do
    it "selects only the slots currently draining" do
      scheduler = build_scheduler
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
      runtime = build_runtime
      scheduler = build_scheduler(runtime: runtime)
      inject_slot(scheduler, build_slot(slot_id: 0, pid: 10, draining: false))

      scheduler.drain_draining_slots

      expect(runtime).not_to have_received(:kill)
    end

    it "stops after pruning when every draining slot already exited naturally", :aggregate_failures do
      status = instance_double(Process::Status, exited?: true)
      runtime = build_runtime(wait2_results: { 10 => [10, status] })
      scheduler = build_scheduler(runtime: runtime, integration: build_integration(build_result))
      inject_slot(scheduler, build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :timeout))

      scheduler.drain_draining_slots

      expect(runtime).not_to have_received(:kill)
      expect(slot_table).to be_empty
    end

    it "broadcasts SIGTERM then SIGKILL and reaps the survivors", :aggregate_failures do
      wakeup = instance_double(Henitai::ProcessWakeup, wait: nil, drain: nil)
      runtime = build_runtime
      calls = []
      allow(runtime).to receive(:kill) { |signal, pid| calls << [signal, pid] }
      scheduler = build_scheduler(
        runtime: runtime, wakeup: wakeup,
        integration: build_integration(build_result(status: :timeout))
      )
      inject_slot(scheduler, build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :timeout))

      scheduler.drain_draining_slots

      expect(calls).to eq([[:SIGTERM, -10], [:SIGKILL, -10]])
      expect(wakeup).to have_received(:wait).with(Henitai::SlotScheduler::PROCESS_DRAIN_WINDOW)
      expect(slot_table).to be_empty
    end
  end

  describe "#prune_raced_draining_slots" do
    it "removes and completes a slot whose pid already exited", :aggregate_failures do
      status = instance_double(Process::Status, exited?: true)
      scheduler = build_scheduler(
        wait2_results: { 10 => [10, status] }, integration: build_integration(build_result)
      )
      slot = build_slot(slot_id: 0, pid: 10, draining: true)
      inject_slot(scheduler, slot)
      draining = { 0 => slot }

      scheduler.send(:prune_raced_draining_slots, draining)

      expect(draining).to be_empty
      expect(slot_table).to be_empty
    end

    it "keeps a slot whose pid has not exited yet" do
      scheduler = build_scheduler
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
      scheduler = build_scheduler(wakeup: wakeup)

      scheduler.send(:wait_for_drain_window)

      expect(wakeup).to have_received(:wait).with(Henitai::SlotScheduler::PROCESS_DRAIN_WINDOW)
      expect(wakeup).to have_received(:drain)
    end

    it "does not raise when there is no wakeup" do
      scheduler = build_scheduler(wakeup: nil)

      expect { scheduler.send(:wait_for_drain_window) }.not_to raise_error
    end
  end

  describe "#signal_draining_slots" do
    it "sends SIGKILL to every draining slot's process group", :aggregate_failures do
      runtime = build_runtime
      scheduler = build_scheduler(runtime: runtime)
      slot_a = build_slot(slot_id: 0, pid: 10, draining: true)
      slot_b = build_slot(slot_id: 1, pid: 11, draining: true)

      scheduler.send(:signal_draining_slots, { 0 => slot_a, 1 => slot_b })

      expect(runtime).to have_received(:kill).with(:SIGKILL, -10)
      expect(runtime).to have_received(:kill).with(:SIGKILL, -11)
    end
  end

  describe "#broadcast_term" do
    it "stamps term_sent_at_monotonic and sends SIGTERM to each slot", :aggregate_failures do
      runtime = build_runtime(now: 42.0)
      scheduler = build_scheduler(runtime: runtime)
      slot = build_slot(slot_id: 0, pid: 10, draining: true)

      scheduler.send(:broadcast_term, { 0 => slot })

      expect(slot.term_sent_at_monotonic).to eq(42.0)
      expect(runtime).to have_received(:kill).with(:SIGTERM, -10)
    end
  end

  describe "#reap_and_finalize_slot" do
    it "skips the blocking reap when the targeted WNOHANG already found an exit status" do
      status = instance_double(Process::Status, exited?: true)
      runtime = build_runtime(wait2_results: { 10 => [10, status] })
      scheduler = build_scheduler(runtime: runtime, integration: build_integration(build_result))
      slot = build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :timeout)
      inject_slot(scheduler, slot)

      scheduler.send(:reap_and_finalize_slot, slot)

      expect(runtime).not_to have_received(:wait)
    end

    it "performs a blocking reap when the targeted WNOHANG found nothing" do
      runtime = build_runtime(wait2_results: { 10 => [nil, nil] })
      scheduler = build_scheduler(runtime: runtime, integration: build_integration(build_result))
      slot = build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :timeout)
      inject_slot(scheduler, slot)

      scheduler.send(:reap_and_finalize_slot, slot)

      expect(runtime).to have_received(:wait).with(10)
    end

    it "removes the slot from both tables and reports it to SchedulerDiagnostics", :aggregate_failures do
      scheduler = build_scheduler(
        wait2_results: { 10 => [nil, nil] }, integration: build_integration(build_result)
      )
      allow(Henitai::Integration::SchedulerDiagnostics).to receive(:child_ended)
      slot = build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :timeout)
      inject_slot(scheduler, slot)

      scheduler.send(:reap_and_finalize_slot, slot)

      expect(slot_table).to be_empty
      expect(slot_table.pid_registered?(10)).to be(false)
      expect(Henitai::Integration::SchedulerDiagnostics).to have_received(:child_ended).with(10)
    end

    it "records no result for an interrupted slot" do
      scheduler = build_scheduler(wait2_results: { 10 => [nil, nil] })
      slot = build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :interrupted)
      inject_slot(scheduler, slot)

      scheduler.send(:reap_and_finalize_slot, slot)

      expect(scheduler.results).to be_empty
    end

    it "records a result for a non-interrupted slot" do
      killed = build_result
      scheduler = build_scheduler(
        wait2_results: { 10 => [nil, nil] }, integration: build_integration(killed)
      )
      slot = build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :timeout)
      inject_slot(scheduler, slot)

      scheduler.send(:reap_and_finalize_slot, slot)

      expect(scheduler.results).to eq([killed])
    end

    it "records a result for a forced_outcome that sorts before :interrupted" do
      killed = build_result
      scheduler = build_scheduler(
        wait2_results: { 10 => [nil, nil] }, integration: build_integration(killed)
      )
      slot = build_slot(slot_id: 0, pid: 10, draining: true, forced_outcome: :aborted)
      inject_slot(scheduler, slot)

      scheduler.send(:reap_and_finalize_slot, slot)

      expect(scheduler.results).to eq([killed])
    end
  end

  describe "#record_drain_result" do
    it "sets mutant status, appends the result, and reports progress", :aggregate_failures do
      progress_reporter = double("progress_reporter") # rubocop:disable RSpec/VerifiedDoubles -- avoid loading Reporter::Terminal/unparser just to stub #progress
      allow(progress_reporter).to receive(:progress)
      killed = instance_double(Henitai::ScenarioExecutionResult, status: :killed)
      scheduler = build_scheduler(
        progress_reporter: progress_reporter, integration: build_integration(killed)
      )
      slot = build_slot(slot_id: 0, pid: 10, forced_outcome: :timeout)

      scheduler.send(:record_drain_result, slot, nil)

      expect(slot.mutant.status).to eq(:killed)
      expect(scheduler.results).to eq([killed])
      expect(progress_reporter).to have_received(:progress).with(slot.mutant, scenario_result: killed)
    end
  end
end
