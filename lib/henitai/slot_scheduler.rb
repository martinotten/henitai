# frozen_string_literal: true

require_relative "slot_scheduler/process_control"
require_relative "slot_scheduler/draining"

module Henitai
  # Owns the process-slot table for a single parallel mutation run.
  #
  # {ProcessWorkerRunner} drives the event loop and OS signal handling and
  # delegates every slot operation here: filling idle slots, reaping completed
  # children, retrying flaky survivors, detecting timeouts and running the
  # drain/broadcast state machine. Keeping the table behind one collaborator
  # means Process.wait* has a single caller, so there are no races between
  # threads reaping the same child.
  #
  # The drain/timeout state machine lives in {Draining}; the low-level process
  # and signal primitives live in {ProcessControl}. +host+ is the owning
  # {ProcessWorkerRunner}, which supplies +runtime+, +wakeup+, +worker_count+
  # and the shutdown flag.
  class SlotScheduler
    include ProcessControl
    include Draining

    PROCESS_DRAIN_WINDOW = 0.2

    # Environment variable exposing a stable worker-slot index (0..jobs-1) to
    # each forked child so test suites can isolate shared resources per slot
    # (e.g. "myapp_test_#{ENV['HENITAI_WORKER_SLOT']}"). A flaky-retry respawn
    # keeps the original attempt's value.
    WORKER_SLOT_ENV = "HENITAI_WORKER_SLOT"

    # Tracks one in-flight mutant child process.
    Slot = Struct.new(
      :slot_id, :mutant, :pid, :started_at_monotonic, :timeout,
      :log_paths, :retry_count, :draining, :term_sent_at_monotonic,
      :forced_outcome, :worker_index
    )

    # @return [Integer] mutants that required at least one retry during the run.
    # @return [Array<ScenarioExecutionResult>] verdicts accumulated so far.
    attr_reader :flaky_retry_count, :results

    def initialize(integration:, config:, progress_reporter:, options:, host:)
      @integration = integration
      @config = config
      @progress_reporter = progress_reporter
      @options = options
      @host = host
      @pending = []
      @slots = {}
      @pid_to_slot = {}
      @results = []
      @flaky_retry_count = 0
      @next_slot_id = 0
    end

    # Queues the mutants to be scheduled into worker slots.
    def enqueue(mutants)
      @pending = mutants.dup
    end

    def done?
      pending.empty? && slots.empty?
    end

    def fill_idle_slots
      while slots.size < worker_count && !pending.empty?
        mutant = pending.shift
        spawn_into_slot(mutant)
      end
    end

    def reap_all_completed_children
      loop do
        pid, status = runtime.wait2(-1, Process::WNOHANG)
        break unless pid

        complete_slot(pid, status)
      end
    rescue Errno::ECHILD
      nil
    end

    def next_event_timeout
      now = monotonic_time
      slot_timeouts = slots.each_value.filter_map do |slot|
        remaining_slot_timeout(slot, now)
      end

      slot_timeouts.min
    end

    private

    attr_reader :pending, :slots, :pid_to_slot, :integration, :config,
                :progress_reporter, :options, :host

    def worker_count = host.worker_count
    def runtime = host.runtime
    def wakeup = host.wakeup
    def shutdown? = host.shutdown_requested?

    def spawn_into_slot(mutant)
      test_files = resolve_test_files(mutant)
      mutant.covered_by = test_files if mutant.respond_to?(:covered_by=)
      mutant.tests_completed = test_files.size if mutant.respond_to?(:tests_completed=)
      worker_index = next_free_worker_index
      ENV[WORKER_SLOT_ENV] = worker_index.to_s
      handle = integration.spawn_mutant(mutant: mutant, test_files: test_files)
      register_slot(handle, mutant, worker_index)
    rescue StandardError => e
      record_spawn_failure(mutant, e)
    end

    def register_slot(handle, mutant, worker_index)
      slot_id = next_slot_id!
      slot = build_slot(slot_id, mutant, handle, worker_index)
      slots[slot_id] = slot
      pid_to_slot[handle.pid] = slot_id
      Integration::SchedulerDiagnostics.child_started(handle.pid)
    end

    def build_slot(slot_id, mutant, handle, worker_index)
      Slot.new(
        slot_id, mutant, handle.pid,
        monotonic_time,
        config.timeout, handle.log_paths, 0, false, nil, nil,
        worker_index
      )
    end

    # Smallest index in 0...worker_count not held by a live slot, so
    # concurrently-running children always see distinct values and freed
    # indices are reused. Slot ids themselves grow monotonically and are
    # unsuitable as a resource token.
    def next_free_worker_index
      used = slots.each_value.map(&:worker_index)
      (0...worker_count).find { |index| !used.include?(index) } || used.size
    end

    def complete_slot(pid, wait_result)
      slot_id = pid_to_slot.delete(pid)
      return unless slot_id

      slot = slots[slot_id]
      return unless slot

      Integration::SchedulerDiagnostics.child_ended(pid)
      result = integration.build_result(wait_result, slot.log_paths)
      dispatch_slot_result(slot, result)
    end

    def dispatch_slot_result(slot, result)
      if should_retry?(slot, result)
        retry_slot(slot)
      else
        slots.delete(slot.slot_id)
        slot.mutant.status = result.status
        results << result
        progress_reporter&.progress(slot.mutant, scenario_result: result)
      end
    end

    def should_retry?(slot, result)
      !shutdown? && result.survived? && slot.retry_count < config.max_flaky_retries.to_i
    end

    def retry_slot(slot)
      test_files = resolve_test_files(slot.mutant)
      ENV[WORKER_SLOT_ENV] = slot.worker_index.to_s
      handle = integration.spawn_mutant(mutant: slot.mutant, test_files: test_files)
      finish_retry(slot, handle)
    rescue StandardError => e
      slots.delete(slot.slot_id)
      record_spawn_failure(slot.mutant, e)
    end

    def finish_retry(slot, handle)
      @flaky_retry_count += 1 if slot.retry_count.zero?
      slot.retry_count += 1
      reset_slot_for_retry(slot, handle)
      pid_to_slot[handle.pid] = slot.slot_id
      Integration::SchedulerDiagnostics.child_started(handle.pid)
    end

    def reset_slot_for_retry(slot, handle)
      slot.pid = handle.pid
      slot.log_paths = handle.log_paths
      slot.started_at_monotonic = monotonic_time
      slot.draining = false
      slot.term_sent_at_monotonic = nil
      slot.forced_outcome = nil
    end

    def record_spawn_failure(mutant, error)
      result = ScenarioExecutionResult.new(
        status: :compile_error,
        stdout: "",
        stderr: "spawn failed: #{error.message}",
        log_path: "/dev/null",
        exit_status: nil
      )
      mutant.status = result.status
      results << result
      progress_reporter&.progress(mutant, scenario_result: result)
    end

    def remaining_slot_timeout(slot, now)
      # Invariant: drain_draining_slots runs (and removes draining slots) before
      # the event wait, so next_event_timeout never observes a draining slot
      # whose SIGTERM has not been sent. Guard term_sent_at_monotonic defensively
      # against a future ordering change: an unsignalled draining slot is due now.
      return 0.0 if slot.draining && slot.term_sent_at_monotonic.nil?

      deadline =
        if slot.draining
          slot.term_sent_at_monotonic + PROCESS_DRAIN_WINDOW
        else
          slot.started_at_monotonic + slot.timeout
        end
      remaining = deadline - now
      remaining.positive? ? remaining : 0.0
    end

    def resolve_test_files(mutant)
      if @options.key?(:test_file_resolver)
        @options[:test_file_resolver].call(mutant)
      elsif @options.key?(:test_files)
        @options[:test_files]
      else
        integration.select_tests(mutant.subject)
      end
    end

    def next_slot_id!
      id = @next_slot_id
      @next_slot_id += 1
      id
    end
  end
end
