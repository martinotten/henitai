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

  # `integration:` and `host:` are injectable so an example can hold onto the
  # collaborator it asserts against instead of reaching back through the
  # scheduler's private readers.
  def build_worker_scheduler(captured, worker_count:, max_flaky_retries: 0, **opts)
    described_class.new(
      integration: opts[:integration] || build_capturing_integration(captured),
      config: Struct.new(:timeout, :max_flaky_retries).new(10.0, max_flaky_retries),
      progress_reporter: opts[:progress_reporter],
      options: opts[:options] || { test_files: [] },
      host: opts[:host] || build_host(worker_count, shutdown: opts.fetch(:shutdown, false))
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

    it "stamps the slot with a real monotonic start time" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1)
      scheduler.enqueue([build_worker_mutant("a")])

      scheduler.fill_idle_slots

      slot = scheduler.send(:slots).values.first
      expect(slot.started_at_monotonic).to be_a(Float).and be > 0.0
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
      integration = build_capturing_integration(captured)
      allow(integration).to receive(:build_result).and_return(
        instance_double(Henitai::ScenarioExecutionResult, survived?: false, status: :killed)
      )
      host = build_host(2)
      scheduler = build_worker_scheduler(captured, worker_count: 2, integration: integration, host: host)
      scheduler.enqueue([build_worker_mutant("a"), build_worker_mutant("b")])
      scheduler.fill_idle_slots
      pids = scheduler.send(:slots).values.map(&:pid)
      status_a = instance_double(Process::Status)
      status_b = instance_double(Process::Status)
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

  describe "#complete_slot" do
    it "does nothing when the pid is unknown", :aggregate_failures do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1)
      scheduler.enqueue([build_worker_mutant("a")])
      scheduler.fill_idle_slots

      expect { scheduler.send(:complete_slot, 999_999, nil) }.not_to raise_error
      expect(scheduler.send(:slots).size).to eq(1)
    end

    it "does nothing when the slot table has no entry for the pid" do
      scheduler = build_scheduler
      scheduler.send(:pid_to_slot)[42] = "stale-slot-id"

      expect { scheduler.send(:complete_slot, 42, nil) }.not_to raise_error
    end

    it "reports the pid to SchedulerDiagnostics and builds the result", :aggregate_failures do
      captured = []
      integration = build_capturing_integration(captured)
      scheduler = build_worker_scheduler(captured, worker_count: 1, integration: integration)
      scheduler.enqueue([build_worker_mutant("a")])
      scheduler.fill_idle_slots
      slot = scheduler.send(:slots).values.first
      allow(Henitai::Integration::SchedulerDiagnostics).to receive(:child_ended)
      killed = instance_double(Henitai::ScenarioExecutionResult, survived?: false, status: :killed)
      allow(integration).to receive(:build_result).with(:wait_result, slot.log_paths).and_return(killed)

      scheduler.send(:complete_slot, slot.pid, :wait_result)

      expect(Henitai::Integration::SchedulerDiagnostics).to have_received(:child_ended).with(slot.pid)
      expect(slot.mutant.status).to eq(:killed)
    end
  end

  describe "#dispatch_slot_result" do
    it "removes the slot, records the result, and reports progress", :aggregate_failures do
      captured = []
      progress_reporter = double("progress_reporter") # rubocop:disable RSpec/VerifiedDoubles -- avoid loading Reporter::Terminal/unparser just to stub #progress
      allow(progress_reporter).to receive(:progress)
      scheduler = build_worker_scheduler(captured, worker_count: 1, progress_reporter: progress_reporter)
      mutant = build_worker_mutant("a")
      scheduler.enqueue([mutant])
      scheduler.fill_idle_slots
      slot = scheduler.send(:slots).values.first
      killed = instance_double(Henitai::ScenarioExecutionResult, survived?: false, status: :killed)

      scheduler.send(:dispatch_slot_result, slot, killed)

      expect(scheduler.send(:slots)).to be_empty
      expect(mutant.status).to eq(:killed)
      expect(scheduler.results).to eq([killed])
      expect(progress_reporter).to have_received(:progress).with(mutant, scenario_result: killed)
    end

    it "retries instead of finalizing when should_retry? is true", :aggregate_failures do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1, max_flaky_retries: 1)
      scheduler.enqueue([build_worker_mutant("a")])
      scheduler.fill_idle_slots
      slot = scheduler.send(:slots).values.first
      survived = instance_double(Henitai::ScenarioExecutionResult, survived?: true, status: :survived)

      scheduler.send(:dispatch_slot_result, slot, survived)

      expect(scheduler.results).to be_empty
      expect(scheduler.flaky_retry_count).to eq(1)
    end
  end

  describe "#should_retry?" do
    def build_slot_with_retry_count(count)
      Henitai::SlotScheduler::Slot.new(1, nil, 12, 0.0, 5.0, nil, count, false, nil, nil, 0)
    end

    it "is false when shutdown has been requested" do
      scheduler = described_class.new(
        integration: nil, config: Struct.new(:max_flaky_retries).new(3),
        progress_reporter: nil, options: {}, host: build_host(1, shutdown: true)
      )
      survived = instance_double(Henitai::ScenarioExecutionResult, survived?: true)

      expect(scheduler.send(:should_retry?, build_slot_with_retry_count(0), survived)).to be(false)
    end

    it "is false when the result did not survive" do
      scheduler = described_class.new(
        integration: nil, config: Struct.new(:max_flaky_retries).new(3),
        progress_reporter: nil, options: {}, host: build_host(1)
      )
      killed = instance_double(Henitai::ScenarioExecutionResult, survived?: false)

      expect(scheduler.send(:should_retry?, build_slot_with_retry_count(0), killed)).to be(false)
    end

    it "is true when retry_count is one below the max" do
      scheduler = described_class.new(
        integration: nil, config: Struct.new(:max_flaky_retries).new(3),
        progress_reporter: nil, options: {}, host: build_host(1)
      )
      survived = instance_double(Henitai::ScenarioExecutionResult, survived?: true)

      expect(scheduler.send(:should_retry?, build_slot_with_retry_count(2), survived)).to be(true)
    end

    it "is false once retry_count reaches the max exactly" do
      scheduler = described_class.new(
        integration: nil, config: Struct.new(:max_flaky_retries).new(3),
        progress_reporter: nil, options: {}, host: build_host(1)
      )
      survived = instance_double(Henitai::ScenarioExecutionResult, survived?: true)

      expect(scheduler.send(:should_retry?, build_slot_with_retry_count(3), survived)).to be(false)
    end

    it "is false when retry_count already exceeds the max" do
      scheduler = described_class.new(
        integration: nil, config: Struct.new(:max_flaky_retries).new(3),
        progress_reporter: nil, options: {}, host: build_host(1)
      )
      survived = instance_double(Henitai::ScenarioExecutionResult, survived?: true)

      expect(scheduler.send(:should_retry?, build_slot_with_retry_count(4), survived)).to be(false)
    end

    it "coerces a string max_flaky_retries to an integer for comparison" do
      scheduler = described_class.new(
        integration: nil, config: Struct.new(:max_flaky_retries).new("3"),
        progress_reporter: nil, options: {}, host: build_host(1)
      )
      survived = instance_double(Henitai::ScenarioExecutionResult, survived?: true)

      expect(scheduler.send(:should_retry?, build_slot_with_retry_count(2), survived)).to be(true)
    end
  end

  describe "#retry_slot" do
    it "respawns with the slot's mutant and resolved test files", :aggregate_failures do
      captured = []
      integration = build_capturing_integration(captured)
      scheduler = build_worker_scheduler(
        captured, worker_count: 1, max_flaky_retries: 1, integration: integration,
                  options: { test_files: %w[a_spec.rb] }
      )
      mutant = build_worker_mutant("a")
      scheduler.enqueue([mutant])
      scheduler.fill_idle_slots
      slot = scheduler.send(:slots).values.first
      original_pid = slot.pid

      scheduler.send(:retry_slot, slot)

      expect(integration).to have_received(:spawn_mutant).with(mutant: mutant, test_files: %w[a_spec.rb]).twice
      expect(slot.pid).not_to eq(original_pid)
      expect(scheduler.send(:pid_to_slot)[slot.pid]).to eq(slot.slot_id)
    end

    it "records a spawn failure and drops the slot when the respawn raises", :aggregate_failures do
      integration = instance_double(Henitai::Integration::Rspec)
      allow(integration).to receive_messages(select_tests: [], spawn_mutant: Henitai::Integration::ChildHandle.new(
        2000, { stdout_path: "/dev/null", stderr_path: "/dev/null", log_path: "/dev/null" }
      ))
      scheduler = described_class.new(
        integration: integration, config: Struct.new(:timeout, :max_flaky_retries).new(10.0, 1),
        progress_reporter: nil, options: { test_files: [] }, host: build_host(1)
      )
      mutant = build_worker_mutant("a")
      scheduler.enqueue([mutant])
      scheduler.fill_idle_slots
      slot = scheduler.send(:slots).values.first
      allow(integration).to receive(:spawn_mutant).and_raise(StandardError, "respawn failed")

      scheduler.send(:retry_slot, slot)

      expect(scheduler.send(:slots)).to be_empty
      expect(scheduler.results.size).to eq(1)
      expect(scheduler.results.first.status).to eq(:compile_error)
      expect(mutant.status).to eq(:compile_error)
    end

    it "resolves test files through integration.select_tests using the slot's own mutant" do
      captured = []
      integration = build_capturing_integration(captured)
      scheduler = build_worker_scheduler(
        captured, worker_count: 1, max_flaky_retries: 1, integration: integration, options: {}
      )
      mutant = build_worker_mutant("a")
      allow(integration).to receive(:select_tests).and_return(%w[a_spec.rb])
      scheduler.enqueue([mutant])
      scheduler.fill_idle_slots
      slot = scheduler.send(:slots).values.first
      allow(integration).to receive(:select_tests).with(mutant.subject).and_return(%w[b_spec.rb])

      scheduler.send(:retry_slot, slot)

      expect(integration).to have_received(:spawn_mutant).with(mutant: mutant, test_files: %w[b_spec.rb])
    end
  end

  describe "#finish_retry" do
    it "counts the first retry toward flaky_retry_count but not later ones", :aggregate_failures do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1, max_flaky_retries: 2)
      scheduler.enqueue([build_worker_mutant("a")])
      scheduler.fill_idle_slots
      slot = scheduler.send(:slots).values.first
      survived = instance_double(Henitai::ScenarioExecutionResult, survived?: true, status: :survived)

      scheduler.send(:dispatch_slot_result, slot, survived)
      expect(scheduler.flaky_retry_count).to eq(1)

      scheduler.send(:dispatch_slot_result, slot, survived)
      expect(scheduler.flaky_retry_count).to eq(1)
    end

    it "increments the slot's retry_count on every retry" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1, max_flaky_retries: 2)
      scheduler.enqueue([build_worker_mutant("a")])
      scheduler.fill_idle_slots
      slot = scheduler.send(:slots).values.first
      survived = instance_double(Henitai::ScenarioExecutionResult, survived?: true, status: :survived)

      scheduler.send(:dispatch_slot_result, slot, survived)

      expect(slot.retry_count).to eq(1)
    end

    it "reports the new pid to SchedulerDiagnostics" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1, max_flaky_retries: 1)
      scheduler.enqueue([build_worker_mutant("a")])
      scheduler.fill_idle_slots
      slot = scheduler.send(:slots).values.first
      survived = instance_double(Henitai::ScenarioExecutionResult, survived?: true, status: :survived)
      allow(Henitai::Integration::SchedulerDiagnostics).to receive(:child_started)

      scheduler.send(:dispatch_slot_result, slot, survived)

      expect(Henitai::Integration::SchedulerDiagnostics).to have_received(:child_started).with(slot.pid)
    end
  end

  describe "#reset_slot_for_retry" do
    it "clears drain state and refreshes pid/log_paths/start time", :aggregate_failures do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1, max_flaky_retries: 1)
      scheduler.enqueue([build_worker_mutant("a")])
      scheduler.fill_idle_slots
      slot = scheduler.send(:slots).values.first
      slot.draining = true
      slot.term_sent_at_monotonic = 5.0
      slot.forced_outcome = :timeout
      slot.started_at_monotonic = 0.0
      original_pid = slot.pid
      handle = Henitai::Integration::ChildHandle.new(
        9999, { stdout_path: "/new", stderr_path: "/new", log_path: "/new" }
      )

      scheduler.send(:reset_slot_for_retry, slot, handle)

      expect(slot.pid).to eq(9999)
      expect(slot.pid).not_to eq(original_pid)
      expect(slot.log_paths).to eq({ stdout_path: "/new", stderr_path: "/new", log_path: "/new" })
      expect(slot.draining).to be(false)
      expect(slot.term_sent_at_monotonic).to be_nil
      expect(slot.forced_outcome).to be_nil
      expect(slot.started_at_monotonic).to be_a(Float).and be > 0.0
    end
  end

  describe "#record_spawn_failure" do
    it "reports the compile_error result to the progress_reporter", :aggregate_failures do
      progress_reporter = double("progress_reporter") # rubocop:disable RSpec/VerifiedDoubles -- avoid loading Reporter::Terminal/unparser just to stub #progress
      allow(progress_reporter).to receive(:progress)
      integration = instance_double(Henitai::Integration::Rspec, select_tests: [])
      allow(integration).to receive(:spawn_mutant).and_raise(StandardError, "boom")
      scheduler = described_class.new(
        integration: integration, config: nil, progress_reporter: progress_reporter,
        options: { test_files: [] }, host: build_host(1)
      )
      mutant = build_worker_mutant("a")
      scheduler.enqueue([mutant])

      scheduler.fill_idle_slots

      expect(progress_reporter).to have_received(:progress).with(mutant, scenario_result: scheduler.results.first)
      result = scheduler.results.first
      expect(result.status).to eq(:compile_error)
      expect(result.stdout).to eq("")
      expect(result.log_path).to eq(File::NULL)
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

    it "restores the parent slot value after initial spawn" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1)
      scheduler.enqueue([build_worker_mutant("a")])

      ENV["HENITAI_WORKER_SLOT"] = "parent"
      scheduler.fill_idle_slots

      expect(ENV.fetch("HENITAI_WORKER_SLOT", nil)).to eq("parent")
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

    it "restores the parent slot value after a flaky retry" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 1, max_flaky_retries: 1)
      scheduler.enqueue([build_worker_mutant("a")])
      scheduler.fill_idle_slots
      survived = instance_double(Henitai::ScenarioExecutionResult, survived?: true, status: :survived)

      ENV["HENITAI_WORKER_SLOT"] = "parent"
      slot = scheduler.send(:slots).values.first
      scheduler.send(:dispatch_slot_result, slot, survived)

      expect(ENV.fetch("HENITAI_WORKER_SLOT", nil)).to eq("parent")
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

      expect(build_scheduler.send(:remaining_slot_timeout, slot, 0.0)).to be(0.0)
    end

    it "uses the drain window once SIGTERM has been sent" do
      slot = Henitai::SlotScheduler::Slot.new(
        1, nil, 12, 0.0, 5.0, nil, 0, true, 1.0, :timeout
      )
      window = Henitai::SlotScheduler::PROCESS_DRAIN_WINDOW

      expect(build_scheduler.send(:remaining_slot_timeout, slot, 1.0)).to be_within(1e-9).of(window)
    end

    it "computes remaining time from started_at_monotonic + timeout for a live slot" do
      slot = Henitai::SlotScheduler::Slot.new(
        1, nil, 12, 10.0, 5.0, nil, 0, false, nil, nil
      )

      expect(build_scheduler.send(:remaining_slot_timeout, slot, 12.0)).to eq(3.0)
    end

    it "clips a negative remaining time to 0.0 for a live slot past its deadline" do
      slot = Henitai::SlotScheduler::Slot.new(
        1, nil, 12, 10.0, 5.0, nil, 0, false, nil, nil
      )

      expect(build_scheduler.send(:remaining_slot_timeout, slot, 20.0)).to eq(0.0)
    end
  end

  describe "#resolve_test_files" do
    it "uses the test_file_resolver option when present, passing it the mutant" do
      mutant = build_worker_mutant("a")
      resolver = ->(m) { m == mutant ? %w[resolved_spec.rb] : [] }
      scheduler = described_class.new(
        integration: nil, config: nil, progress_reporter: nil,
        options: { test_file_resolver: resolver, test_files: %w[ignored_spec.rb] }, host: nil
      )

      expect(scheduler.send(:resolve_test_files, mutant)).to eq(%w[resolved_spec.rb])
    end

    it "falls back to the static test_files option when no resolver is set" do
      scheduler = described_class.new(
        integration: nil, config: nil, progress_reporter: nil,
        options: { test_files: %w[static_spec.rb] }, host: nil
      )

      expect(scheduler.send(:resolve_test_files, build_worker_mutant("a"))).to eq(%w[static_spec.rb])
    end

    it "falls back to integration.select_tests when neither option is set" do
      mutant = build_worker_mutant("a")
      integration = instance_double(Henitai::Integration::Rspec)
      allow(integration).to receive(:select_tests).with(mutant.subject).and_return(%w[selected_spec.rb])
      scheduler = described_class.new(
        integration: integration, config: nil, progress_reporter: nil, options: {}, host: nil
      )

      expect(scheduler.send(:resolve_test_files, mutant)).to eq(%w[selected_spec.rb])
    end
  end
end
