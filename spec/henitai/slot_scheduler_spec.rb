# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SlotScheduler do
  def build_scheduler
    described_class.new(
      integration: nil,
      config: nil,
      progress_reporter: nil,
      options: {},
      host: nil
    )
  end

  def build_worker_mutant(id)
    subject = Struct.new(:expression).new("Foo##{id}")
    Struct.new(:id, :subject, :status, :covered_by, :tests_completed) do
      def pending? = status == :pending
    end.new(id, subject, :pending)
  end

  def build_host(worker_count, runtime: Henitai::ProcessWorkerRunner::Runtime.new, wakeup: nil, shutdown: false)
    host_struct = Struct.new(:worker_count, :runtime, :wakeup) do
      define_method(:shutdown_requested?) { shutdown }
    end
    host_struct.new(worker_count, runtime, wakeup)
  end

  def build_capturing_integration(captured)
    integration = instance_double(Henitai::Integration::Rspec)
    pids = (1000..).each
    allow(integration).to receive(:spawn_mutant) do |**|
      captured << ENV.fetch("HENITAI_WORKER_SLOT", nil)
      Henitai::Integration::ChildHandle.new(
        pids.next,
        { stdout_path: "/dev/null", stderr_path: "/dev/null", log_path: "/dev/null" }
      )
    end
    integration
  end

  def build_worker_scheduler(captured, worker_count:, max_flaky_retries: 0, options: { test_files: [] })
    described_class.new(
      integration: build_capturing_integration(captured),
      config: Struct.new(:timeout, :max_flaky_retries).new(10.0, max_flaky_retries),
      progress_reporter: nil,
      options: options,
      host: build_host(worker_count)
    )
  end

  describe "#initialize" do
    it "starts with empty pending, slots, results, and retries", :aggregate_failures do
      scheduler = build_scheduler

      expect(scheduler.done?).to be(true)
      expect(scheduler.results).to eq([])
      expect(scheduler.flaky_retry_count).to eq(0)
    end
  end

  describe "#done?" do
    it "is true when both pending and slots are empty" do
      expect(build_scheduler.done?).to be(true)
    end

    it "is false when a mutant is pending but no slot is active" do
      scheduler = build_scheduler
      scheduler.enqueue([build_worker_mutant("a")])

      expect(scheduler.done?).to be(false)
    end

    it "is false when a slot is active but nothing is pending" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1)
      scheduler.enqueue([build_worker_mutant("a")])
      scheduler.fill_idle_slots

      expect(scheduler.done?).to be(false)
    end
  end

  describe "delegated host readers" do
    it "delegates worker_count/runtime/wakeup/shutdown? to host", :aggregate_failures do
      host = instance_double(
        Henitai::ProcessWorkerRunner,
        worker_count: 4,
        runtime: :the_runtime,
        wakeup: :the_wakeup,
        shutdown_requested?: true
      )
      scheduler = described_class.new(
        integration: nil, config: nil, progress_reporter: nil, options: {}, host: host
      )

      expect(scheduler.send(:worker_count)).to eq(4)
      expect(scheduler.send(:runtime)).to eq(:the_runtime)
      expect(scheduler.send(:wakeup)).to eq(:the_wakeup)
      expect(scheduler.send(:shutdown?)).to be(true)
    end
  end

  describe "#fill_idle_slots" do
    it "spawns up to worker_count slots, leaving the rest pending", :aggregate_failures do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 2)
      scheduler.enqueue([build_worker_mutant("a"), build_worker_mutant("b"), build_worker_mutant("c")])

      scheduler.fill_idle_slots

      expect(scheduler.send(:slots).size).to eq(2)
      expect(scheduler.send(:pending).size).to eq(1)
    end

    it "does not spawn when there is nothing pending" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 2)

      scheduler.fill_idle_slots

      expect(captured).to be_empty
    end

    it "does not spawn when slots already exceed worker_count" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1)
      slots = scheduler.send(:slots)
      # Two live slots against worker_count: 1 forces slots.size(2) > worker_count(1),
      # distinguishing `<` from a `!=` mutation (which would keep spawning at exactly 1).
      2.times { |i| slots[i] = Henitai::SlotScheduler::Slot.new(i, nil, 100 + i, 0.0, 5.0, nil, 0, false, nil, nil, i) }
      scheduler.enqueue([build_worker_mutant("a")])

      scheduler.fill_idle_slots

      expect(captured).to be_empty
    end
  end

  describe "#spawn_into_slot" do
    it "sets covered_by and tests_completed when supported", :aggregate_failures do
      captured = []
      scheduler = build_worker_scheduler(
        captured, worker_count: 1, options: { test_files: %w[a_spec.rb b_spec.rb] }
      )
      mutant = build_worker_mutant("a")
      scheduler.enqueue([mutant])

      scheduler.fill_idle_slots

      expect(mutant.covered_by).to eq(%w[a_spec.rb b_spec.rb])
      expect(mutant.tests_completed).to eq(2)
    end

    it "tolerates mutants without covered_by=/tests_completed=", :aggregate_failures do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1)
      bare_mutant = Struct.new(:id, :subject, :status) do
        def pending? = true
      end.new("bare", Struct.new(:expression).new("Foo#bare"), :pending)
      scheduler.enqueue([bare_mutant])

      expect { scheduler.fill_idle_slots }.not_to raise_error
      expect(scheduler.send(:slots).size).to eq(1)
    end

    it "records a spawn failure without raising", :aggregate_failures do
      integration = instance_double(Henitai::Integration::Rspec)
      allow(integration).to receive(:spawn_mutant).and_raise(StandardError, "boom")
      allow(integration).to receive(:select_tests).and_return([])
      scheduler = described_class.new(
        integration: integration, config: nil, progress_reporter: nil,
        options: { test_files: [] }, host: build_host(1)
      )
      mutant = build_worker_mutant("a")
      scheduler.enqueue([mutant])

      expect { scheduler.fill_idle_slots }.not_to raise_error
      expect(scheduler.results.size).to eq(1)
      expect(scheduler.results.first.status).to eq(:compile_error)
      expect(scheduler.results.first.stderr).to include("boom")
      expect(mutant.status).to eq(:compile_error)
    end
  end

  describe "#register_slot" do
    it "keys the slot by slot_id and maps pid back to it", :aggregate_failures do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1)
      mutant = build_worker_mutant("a")
      scheduler.enqueue([mutant])

      scheduler.fill_idle_slots

      slot = scheduler.send(:slots).values.first
      expect(slot.mutant).to eq(mutant)
      expect(slot.retry_count).to eq(0)
      expect(slot.draining).to be(false)
      expect(slot.term_sent_at_monotonic).to be_nil
      expect(slot.forced_outcome).to be_nil
      expect(scheduler.send(:pid_to_slot)[slot.pid]).to eq(slot.slot_id)
    end

    it "reports the child pid to SchedulerDiagnostics" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1)
      scheduler.enqueue([build_worker_mutant("a")])
      allow(Henitai::Integration::SchedulerDiagnostics).to receive(:child_started)

      scheduler.fill_idle_slots

      pid = scheduler.send(:slots).values.first.pid
      expect(Henitai::Integration::SchedulerDiagnostics).to have_received(:child_started).with(pid)
    end
  end

  describe "#build_slot" do
    it "carries the handle's log_paths onto the slot" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1)
      scheduler.enqueue([build_worker_mutant("a")])

      scheduler.fill_idle_slots

      slot = scheduler.send(:slots).values.first
      expect(slot.log_paths).to eq(
        { stdout_path: "/dev/null", stderr_path: "/dev/null", log_path: "/dev/null" }
      )
    end
  end

  describe "#reap_all_completed_children" do
    def build_runtime_double(*wait2_results)
      runtime = instance_double(Henitai::ProcessWorkerRunner::Runtime)
      allow(runtime).to receive(:wait2).and_return(*wait2_results, nil)
      runtime
    end

    it "completes every reaped slot until wait2 returns no pid", :aggregate_failures do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 2)
      scheduler.enqueue([build_worker_mutant("a"), build_worker_mutant("b")])
      scheduler.fill_idle_slots
      pids = scheduler.send(:slots).values.map(&:pid)
      status_a = instance_double(Process::Status)
      status_b = instance_double(Process::Status)
      allow(scheduler.send(:integration)).to receive(:build_result).and_return(
        instance_double(Henitai::ScenarioExecutionResult, survived?: false, status: :killed)
      )
      host = scheduler.send(:host)
      allow(host).to receive(:runtime).and_return(
        build_runtime_double([pids[0], status_a], [pids[1], status_b])
      )

      scheduler.reap_all_completed_children

      expect(scheduler.send(:slots)).to be_empty
      expect(scheduler.results.size).to eq(2)
    end

    it "stops without raising when the runtime reports no children" do
      host = build_host(1, runtime: build_runtime_double)
      scheduler = described_class.new(
        integration: nil, config: nil, progress_reporter: nil, options: {}, host: host
      )

      expect { scheduler.reap_all_completed_children }.not_to raise_error
    end

    it "swallows Errno::ECHILD instead of raising" do
      runtime = instance_double(Henitai::ProcessWorkerRunner::Runtime)
      allow(runtime).to receive(:wait2).and_raise(Errno::ECHILD)
      host = build_host(1, runtime: runtime)
      scheduler = described_class.new(
        integration: nil, config: nil, progress_reporter: nil, options: {}, host: host
      )

      expect { scheduler.reap_all_completed_children }.not_to raise_error
    end
  end

  describe "#next_event_timeout" do
    def scheduler_with_runtime_now(now)
      runtime = instance_double(Henitai::ProcessWorkerRunner::Runtime, clock_gettime: now)
      described_class.new(
        integration: nil, config: nil, progress_reporter: nil, options: {},
        host: build_host(1, runtime: runtime)
      )
    end

    it "returns nil when there are no active slots" do
      scheduler = scheduler_with_runtime_now(0.0)

      expect(scheduler.next_event_timeout).to be_nil
    end

    it "returns the smallest remaining timeout across all slots" do
      scheduler = scheduler_with_runtime_now(10.0)
      slots = scheduler.send(:slots)
      slots[0] = Henitai::SlotScheduler::Slot.new(0, nil, 100, 0.0, 5.0, nil, 0, false, nil, nil, 0)
      slots[1] = Henitai::SlotScheduler::Slot.new(1, nil, 101, 0.0, 50.0, nil, 0, false, nil, nil, 1)

      expect(scheduler.next_event_timeout).to eq(0.0)
    end
  end

  describe "#slot_timeout" do
    it "uses config.timeout when no timeout_resolver option is set" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1)
      scheduler.enqueue([build_worker_mutant("a")])

      scheduler.fill_idle_slots

      expect(scheduler.send(:slots).values.first.timeout).to eq(10.0)
    end

    it "uses the timeout_resolver when the option is set" do
      captured = []
      resolver = ->(_mutant, _test_files) { 99.0 }
      scheduler = build_worker_scheduler(
        captured, worker_count: 1, options: { test_files: [], timeout_resolver: resolver }
      )
      scheduler.enqueue([build_worker_mutant("a")])

      scheduler.fill_idle_slots

      expect(scheduler.send(:slots).values.first.timeout).to eq(99.0)
    end
  end

  describe "#next_free_worker_index" do
    def build_idle_scheduler(worker_count)
      described_class.new(
        integration: nil, config: nil, progress_reporter: nil, options: {}, host: build_host(worker_count)
      )
    end

    it "returns 0 when no slots are in use" do
      scheduler = build_idle_scheduler(2)
      expect(scheduler.send(:next_free_worker_index)).to eq(0)
    end

    it "returns the smallest free index among live slots" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 3)
      scheduler.enqueue([build_worker_mutant("a")])
      scheduler.fill_idle_slots
      # Free the assigned worker_index (0) but keep the slot table entry
      # untouched otherwise, then take a second one to prove reuse.
      scheduler.enqueue([build_worker_mutant("b")])

      scheduler.fill_idle_slots

      expect(captured).to eq(%w[0 1])
    end

    it "does not treat worker_count itself as a free index" do
      scheduler = build_idle_scheduler(2)
      slots = scheduler.send(:slots)
      [0, 1, 5].each_with_index do |worker_index, i|
        slots[i] = Henitai::SlotScheduler::Slot.new(
          i, nil, 100 + i, 0.0, 5.0, nil, 0, false, nil, nil, worker_index
        )
      end

      expect(scheduler.send(:next_free_worker_index)).to eq(3)
    end
  end

  describe "#next_slot_id!" do
    it "increments monotonically across calls" do
      scheduler = build_scheduler

      first = scheduler.send(:next_slot_id!)
      second = scheduler.send(:next_slot_id!)

      expect([first, second]).to eq([0, 1])
    end
  end

  describe "HENITAI_WORKER_SLOT" do
    around do |example|
      original = ENV.fetch("HENITAI_WORKER_SLOT", nil)
      example.run
    ensure
      original.nil? ? ENV.delete("HENITAI_WORKER_SLOT") : ENV["HENITAI_WORKER_SLOT"] = original
    end

    it "injects distinct slot values from 0..jobs-1 at initial spawn" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 2)
      scheduler.enqueue([build_worker_mutant("a"), build_worker_mutant("b"), build_worker_mutant("c")])

      scheduler.fill_idle_slots

      expect(captured).to eq(%w[0 1])
    end

    it "keeps the original slot value on a flaky-retry respawn" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 2, max_flaky_retries: 1)
      scheduler.enqueue([build_worker_mutant("a"), build_worker_mutant("b")])
      scheduler.fill_idle_slots
      survived = instance_double(Henitai::ScenarioExecutionResult, survived?: true, status: :survived)

      slot_one = scheduler.send(:slots).values.last
      scheduler.send(:dispatch_slot_result, slot_one, survived)

      expect(captured).to eq(%w[0 1 1])
    end

    it "reuses a freed slot value for the next spawn" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 2)
      scheduler.enqueue([build_worker_mutant("a"), build_worker_mutant("b"), build_worker_mutant("c")])
      scheduler.fill_idle_slots
      killed = instance_double(Henitai::ScenarioExecutionResult, survived?: false, status: :killed)

      slot_zero = scheduler.send(:slots).values.first
      scheduler.send(:dispatch_slot_result, slot_zero, killed)
      scheduler.fill_idle_slots

      expect(captured).to eq(%w[0 1 0])
    end
  end

  describe "#remaining_slot_timeout draining invariant" do
    it "treats a draining slot with no SIGTERM timestamp as due immediately" do
      slot = Henitai::SlotScheduler::Slot.new(
        1, nil, 12, 0.0, 5.0, nil, 0, true, nil, :timeout
      )

      expect(build_scheduler.send(:remaining_slot_timeout, slot, 0.0)).to eq(0.0)
    end

    it "uses the drain window once SIGTERM has been sent" do
      slot = Henitai::SlotScheduler::Slot.new(
        1, nil, 12, 0.0, 5.0, nil, 0, true, 1.0, :timeout
      )
      window = Henitai::SlotScheduler::PROCESS_DRAIN_WINDOW

      expect(build_scheduler.send(:remaining_slot_timeout, slot, 1.0)).to be_within(1e-9).of(window)
    end
  end
end
