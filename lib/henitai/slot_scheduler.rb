# frozen_string_literal: true

require_relative "slot_scheduler/process_control"
require_relative "slot_scheduler/draining"
require_relative "slot_scheduler/drain_verdict"
require_relative "slot_scheduler/retry_policy"
require_relative "slot_scheduler/slot_deadline"
require_relative "slot_scheduler/slot_table"
require_relative "slot_scheduler/test_file_selection"

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

    # +slot_table+ is injectable so a spec can seed mid-run state, or assert
    # against the table through its own public interface, without reaching a
    # private reader here.
    # rubocop:disable Metrics/ParameterLists -- every one of these is a distinct
    # collaborator supplied by ProcessWorkerRunner; bundling them into a context
    # object would only move the list.
    def initialize(integration:, config:, progress_reporter:, options:, host:, slot_table: SlotTable.new)
      # rubocop:enable Metrics/ParameterLists
      @integration = integration
      @config = config
      @progress_reporter = progress_reporter
      @options = options
      @host = host
      @slot_table = slot_table
      @pending = []
      @results = []
      @flaky_retry_count = 0
    end

    # Queues the mutants to be scheduled into worker slots.
    def enqueue(mutants)
      @pending = mutants.dup
    end

    def done?
      pending.empty? && slot_table.empty?
    end

    def fill_idle_slots
      while slot_table.size < worker_count && !pending.empty?
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
      slot_timeouts = slot_table.each_value.filter_map do |slot|
        slot_deadline.remaining(slot, now)
      end

      slot_timeouts.min
    end

    private

    attr_reader :pending, :slot_table, :integration, :config,
                :progress_reporter, :options, :host

    def worker_count = host.worker_count
    def runtime = host.runtime
    def wakeup = host.wakeup
    def shutdown? = host.shutdown_requested?

    def spawn_into_slot(mutant)
      selection = test_file_selection
      test_files = selection.for(mutant)
      annotate_selection(mutant, test_files)
      return record_no_coverage(mutant) if selection.resolved_empty?(test_files)

      worker_index = slot_table.next_free_worker_index(worker_count)
      with_worker_slot(worker_index) do
        handle = integration.spawn_mutant(mutant: mutant, test_files: test_files)
        register_slot(handle, mutant, worker_index, slot_timeout(mutant, test_files))
      end
    rescue StandardError => e
      record_spawn_failure(mutant, e)
    end

    # Reported back onto the mutant so the report can show which tests were
    # considered, whether or not any of them ran. Guarded by respond_to? because
    # specs pass Struct stand-ins without these members.
    def annotate_selection(mutant, test_files)
      mutant.covered_by = test_files if mutant.respond_to?(:covered_by=)
      mutant.tests_completed = test_files.size if mutant.respond_to?(:tests_completed=)
    end

    def register_slot(handle, mutant, worker_index, timeout)
      slot = build_slot(slot_table.next_slot_id!, mutant, handle, worker_index, timeout)
      slot_table.add(slot)
      slot_table.register_pid(handle.pid, slot.slot_id)
      Integration::SchedulerDiagnostics.child_started(handle.pid)
    end

    def build_slot(slot_id, mutant, handle, worker_index, timeout)
      Slot.new(
        slot_id, mutant, handle.pid,
        monotonic_time,
        timeout, handle.log_paths, 0, false, nil, nil,
        worker_index
      )
    end

    def slot_timeout(mutant, test_files)
      resolver = options[:timeout_resolver]
      resolver ? resolver.call(mutant, test_files) : config.timeout
    end

    def complete_slot(pid, wait_result)
      slot_id = slot_table.release_pid(pid)
      return unless slot_id

      slot = slot_table.fetch(slot_id)
      return unless slot

      Integration::SchedulerDiagnostics.child_ended(pid)
      result = integration.build_result(wait_result, slot.log_paths)
      dispatch_slot_result(slot, result)
    end

    def dispatch_slot_result(slot, result)
      return retry_slot(slot) if retry_policy.retry?(slot: slot, result: result, shutdown: shutdown?)

      finalize_slot(slot, result)
    end

    def finalize_slot(slot, result)
      slot_table.delete(slot.slot_id)
      slot.mutant.status = result.status
      results << result
      progress_reporter&.progress(slot.mutant, scenario_result: result)
      result.release_output! if result.respond_to?(:release_output!)
    end

    # Memoized lazily, not built in #initialize: specs (and the no-op scheduler
    # the runner builds when nothing is pending) pass `config: nil`, and this
    # is only reached once a slot has actually finished.
    def retry_policy
      @retry_policy ||= RetryPolicy.new(max_retries: config.max_flaky_retries)
    end

    def drain_verdict
      @drain_verdict ||= DrainVerdict.new(integration: integration)
    end

    def slot_deadline
      @slot_deadline ||= SlotDeadline.new(drain_window: PROCESS_DRAIN_WINDOW)
    end

    def test_file_selection
      @test_file_selection ||= TestFileSelection.new(options: options, integration: integration)
    end

    def retry_slot(slot)
      test_files = test_file_selection.for(slot.mutant)
      with_worker_slot(slot.worker_index) do
        handle = integration.spawn_mutant(mutant: slot.mutant, test_files: test_files)
        finish_retry(slot, handle)
      end
    rescue StandardError => e
      slot_table.delete(slot.slot_id)
      record_spawn_failure(slot.mutant, e)
    end

    def finish_retry(slot, handle)
      @flaky_retry_count += 1 if slot.retry_count.zero?
      slot.retry_count += 1
      reset_slot_for_retry(slot, handle)
      slot_table.register_pid(handle.pid, slot.slot_id)
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

    def record_no_coverage(mutant)
      mutant.status = :no_coverage
      progress_reporter&.progress(mutant, scenario_result: nil)
    end

    def with_worker_slot(worker_index)
      previous = ENV.fetch(WORKER_SLOT_ENV, nil)
      ENV[WORKER_SLOT_ENV] = worker_index.to_s
      yield
    ensure
      if previous.nil?
        ENV.delete(WORKER_SLOT_ENV)
      else
        ENV[WORKER_SLOT_ENV] = previous
      end
    end
  end
end
