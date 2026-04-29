# frozen_string_literal: true

module Henitai
  # Flat, single-threaded process-slot scheduler for parallel mutation runs.
  #
  # Owns the process table: it is the sole caller of Process.wait* so there
  # are no race conditions between threads reaping the same child.
  class ProcessWorkerRunner # rubocop:disable Metrics/ClassLength
    PROCESS_DRAIN_WINDOW = 0.2

    # Default bridge to process and signal primitives used by the scheduler.
    class Runtime
      def clock_gettime(clock_id)
        Process.clock_gettime(clock_id)
      end

      def wait2(pid, flags = nil)
        Process.wait2(pid, flags)
      end

      def kill(signal, pid)
        Process.kill(signal, pid)
      end

      def wait(pid)
        Process.wait(pid)
      end

      def trap(signal, handler = nil, &block)
        Kernel.trap(signal, handler || block)
      end
    end

    # Tracks one in-flight mutant child process.
    Slot = Struct.new(
      :slot_id, :mutant, :pid, :started_at_monotonic, :timeout,
      :log_paths, :retry_count, :draining, :term_sent_at_monotonic,
      :forced_outcome
    )

    def initialize(worker_count:, runtime: Runtime.new, wakeup: nil)
      @worker_count = worker_count
      @runtime = runtime
      @wakeup = wakeup
      @shutdown_requested = false
    end

    # Trigger a graceful shutdown from outside the event loop.
    # Safe to call from any thread. The loop observes the flag on its next tick.
    def request_shutdown
      @shutdown_requested = true
      @wakeup&.signal
    end

    # Runs all mutants and returns an array of ScenarioExecutionResult.
    #
    # @param mutants [Array<Mutant>]
    # @param integration [Integration::Base]
    # @param config [Configuration]
    # @param progress_reporter [#progress, nil]
    # @param options [Hash]
    # @return [Array<ScenarioExecutionResult>]
    def run(mutants, integration, config, progress_reporter, options = {})
      Integration::SchedulerDiagnostics.reset! if Integration::SchedulerDiagnostics.enabled?
      prepare_run(mutants, integration, config, progress_reporter, options)

      event_loop
      @results
    ensure
      @wakeup&.close
      @wakeup = nil
    end

    private

    attr_reader :worker_count, :pending, :slots, :pid_to_slot, :results,
                :integration, :config, :progress_reporter, :runtime

    def event_loop
      saved_traps = install_signal_traps
      loop do
        break if done?

        break if process_cycle == :shutdown
      end
    ensure
      restore_signal_traps(saved_traps)
      raise Interrupt if @shutdown_requested
    end

    def process_cycle
      fill_idle_slots unless @shutdown_requested
      reap_all_completed_children
      check_timeouts
      fill_idle_slots unless @shutdown_requested
      return handle_shutdown if @shutdown_requested

      drain_draining_slots if draining_slots?
      fill_idle_slots unless @shutdown_requested
      return :done if done?

      wait_for_next_event
      nil
    end

    def handle_shutdown
      interrupt_active_slots
      drain_draining_slots
      :shutdown
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

    def spawn_into_slot(mutant)
      test_files = resolve_test_files(mutant)
      mutant.covered_by = test_files if mutant.respond_to?(:covered_by=)
      mutant.tests_completed = test_files.size if mutant.respond_to?(:tests_completed=)
      handle = integration.spawn_mutant(mutant: mutant, test_files: test_files)
      register_slot(handle, mutant)
    rescue StandardError => e
      record_spawn_failure(mutant, e)
    end

    def register_slot(handle, mutant)
      slot_id = next_slot_id!
      slot = build_slot(slot_id, mutant, handle)
      slots[slot_id] = slot
      pid_to_slot[handle.pid] = slot_id
      Integration::SchedulerDiagnostics.child_started(handle.pid)
    end

    def build_slot(slot_id, mutant, handle)
      Slot.new(
        slot_id, mutant, handle.pid,
        monotonic_time,
        config.timeout, handle.log_paths, 0, false, nil, nil
      )
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

    # Per-slot timeout check. Must be called after reap_all_completed_children
    # so that naturally-exited processes are already removed from slots.
    def check_timeouts
      now = monotonic_time
      slots.each_value do |slot|
        next if slot.draining
        next unless now >= slot.started_at_monotonic + slot.timeout

        # Final targeted reap: if the child already exited, classify it normally.
        pid, status = runtime.wait2(slot.pid, Process::WNOHANG)
        if pid
          complete_slot(pid, status)
        else
          slot.forced_outcome = :timeout
          slot.draining = true
        end
      end
    end

    def draining_slots?
      slots.any? { |_, slot| slot.draining }
    end

    # Two-phase broadcast cleanup for all slots that are in draining state.
    #
    # Precision rule: before signalling, do one final WNOHANG pass to catch
    # processes that exited naturally in the window between check_timeouts and
    # now. If SIGTERM gets ESRCH, the process is already gone — we must not
    # force-label those as :timeout.
    def drain_draining_slots
      draining = draining_slots
      return if draining.empty?

      prune_raced_draining_slots(draining)

      return if draining.empty?

      broadcast_term(draining)
      wait_for_drain_window
      signal_draining_slots(draining)
      reap_and_remove_draining(draining)
    end

    def draining_slots
      slots.select { |_, slot| slot.draining }
    end

    def prune_raced_draining_slots(draining)
      draining.reject! do |_, slot|
        pid, status = wnohang_reap(slot.pid)
        next false unless pid

        complete_slot(pid, status)
        true
      end
    end

    def wait_for_drain_window
      @wakeup&.wait(PROCESS_DRAIN_WINDOW)
      @wakeup&.drain
    end

    def signal_draining_slots(draining)
      draining.each_value { |slot| signal_process_group(slot.pid, :SIGKILL) }
    end

    def broadcast_term(draining)
      now = monotonic_time
      draining.each_value do |slot|
        slot.term_sent_at_monotonic = now
        signal_process_group(slot.pid, :SIGTERM)
      end
    end

    # After SIGKILL window: blocking reap each slot, then build its result.
    #
    # Interrupted slots are cleaned up but produce no result — the scheduler
    # is shutting down and does not emit verdicts for in-flight mutants.
    #
    # For timeout slots: a real exit status only wins if observed before any
    # parent signal was sent. Once SIGTERM has been dispatched, the forced
    # outcome is authoritative — a child handling SIGTERM and exiting 0 must
    # not be misclassified as :survived.
    def reap_and_remove_draining(draining) # rubocop:disable Metrics/AbcSize
      draining.each_value do |slot|
        # One last WNOHANG before blocking: catches processes that exited
        # between SIGKILL and here.
        _, final_status = wnohang_reap(slot.pid)
        reap_pid(slot.pid) unless final_status

        pid_to_slot.delete(slot.pid)
        slots.delete(slot.slot_id)
        Integration::SchedulerDiagnostics.child_ended(slot.pid)

        next if slot.forced_outcome == :interrupted

        result = build_drain_result(slot, final_status)
        slot.mutant.status = result.status
        results << result
        progress_reporter&.progress(slot.mutant, scenario_result: result)
      end
    end

    # Choose result: use real exit status only if observed before any parent
    # signal was sent. After SIGTERM, the forced outcome is authoritative.
    def build_drain_result(slot, final_status)
      if final_status&.exited? && slot.term_sent_at_monotonic.nil?
        integration.build_result(final_status, slot.log_paths)
      else
        integration.build_result(slot.forced_outcome || :timeout, slot.log_paths)
      end
    end

    def install_signal_traps
      saved = {}
      %w[INT TERM HUP].each do |sig|
        saved[sig] = runtime.trap(sig) { @shutdown_requested = true }
      end
      saved
    end

    def restore_signal_traps(saved)
      saved&.each { |sig, handler| runtime.trap(sig, handler) }
    end

    def interrupt_active_slots
      slots.each_value do |slot|
        next if slot.draining

        slot.forced_outcome = :interrupted
        slot.draining = true
      end
    end

    def should_retry?(slot, result)
      !@shutdown_requested && result.survived? && slot.retry_count < config.max_flaky_retries.to_i
    end

    def prepare_run(mutants, integration, config, progress_reporter, options)
      @pending = mutants.dup
      @slots = {}
      @pid_to_slot = {}
      @results = []
      @next_slot_id = 0
      @integration = integration
      @config = config
      @progress_reporter = progress_reporter
      @options = options
      @wakeup = Henitai::ProcessWakeup.new.install if @wakeup.nil?
    end

    def next_event_timeout
      now = monotonic_time
      slot_timeouts = slots.each_value.filter_map do |slot|
        remaining_slot_timeout(slot, now)
      end

      slot_timeouts.min
    end

    def remaining_slot_timeout(slot, now)
      deadline =
        if slot.draining
          slot.term_sent_at_monotonic + PROCESS_DRAIN_WINDOW
        else
          slot.started_at_monotonic + slot.timeout
        end
      remaining = deadline - now
      remaining.positive? ? remaining : 0.0
    end

    def wait_for_next_event
      @wakeup&.wait(next_event_timeout)
      @wakeup&.drain
    end

    def retry_slot(slot) # rubocop:disable Metrics/AbcSize
      slot.retry_count += 1
      test_files = resolve_test_files(slot.mutant)
      handle = integration.spawn_mutant(mutant: slot.mutant, test_files: test_files)
      slot.pid = handle.pid
      slot.log_paths = handle.log_paths
      slot.started_at_monotonic = monotonic_time
      slot.draining = false
      slot.term_sent_at_monotonic = nil
      slot.forced_outcome = nil
      pid_to_slot[handle.pid] = slot.slot_id
      Integration::SchedulerDiagnostics.child_started(handle.pid)
    rescue StandardError => e
      slots.delete(slot.slot_id)
      record_spawn_failure(slot.mutant, e)
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

    def wnohang_reap(pid)
      runtime.wait2(pid, Process::WNOHANG)
    rescue Errno::ECHILD, Errno::ESRCH
      nil
    end

    def signal_process_group(pid, signal)
      runtime.kill(signal, -pid)
    rescue Errno::ESRCH
      nil
    rescue Errno::EPERM
      # Process group not yet established; fall back to signalling the pid.
      begin
        runtime.kill(signal, pid)
      rescue Errno::ESRCH
        nil
      end
    end

    def reap_pid(pid)
      runtime.wait(pid)
    rescue Errno::ECHILD, Errno::ESRCH
      nil
    end

    def monotonic_time
      runtime.clock_gettime(Process::CLOCK_MONOTONIC)
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
