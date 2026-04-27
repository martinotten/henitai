# frozen_string_literal: true

module Henitai
  # Flat, single-threaded process-slot scheduler for parallel mutation runs.
  #
  # Owns the process table: it is the sole caller of Process.wait* so there
  # are no race conditions between threads reaping the same child.
  class ProcessWorkerRunner
    SCHEDULER_POLL_INTERVAL = 0.01
    PROCESS_DRAIN_WINDOW = 0.2

    # Tracks one in-flight mutant child process.
    Slot = Struct.new(
      :slot_id, :mutant, :pid, :started_at_monotonic, :timeout,
      :log_paths, :retry_count, :draining, :term_sent_at_monotonic,
      :forced_outcome
    )

    def initialize(worker_count:)
      @worker_count = worker_count
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
      @pending = mutants.dup
      @slots = {}
      @pid_to_slot = {}
      @results = []
      @next_slot_id = 0
      @integration = integration
      @config = config
      @progress_reporter = progress_reporter
      @options = options

      event_loop
      @results
    end

    private

    attr_reader :worker_count, :pending, :slots, :pid_to_slot, :results,
                :integration, :config, :progress_reporter

    def event_loop
      loop do
        break if done?

        fill_idle_slots
        IO.select(nil, nil, nil, SCHEDULER_POLL_INTERVAL)
        reap_all_completed_children
        check_timeouts
        drain_draining_slots if draining_slots?
      end
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
      handle = integration.spawn_mutant(mutant: mutant, test_files: test_files)
      register_slot(handle, mutant)
    end

    def register_slot(handle, mutant)
      slot_id = next_slot_id!
      slot = build_slot(slot_id, mutant, handle)
      slots[slot_id] = slot
      pid_to_slot[handle.pid] = slot_id
    end

    def build_slot(slot_id, mutant, handle)
      Slot.new(
        slot_id, mutant, handle.pid,
        Process.clock_gettime(Process::CLOCK_MONOTONIC),
        config.timeout, handle.log_paths, 0, false, nil, nil
      )
    end

    def reap_all_completed_children
      loop do
        pid, status = Process.wait2(-1, Process::WNOHANG)
        break unless pid

        complete_slot(pid, status)
      end
    rescue Errno::ECHILD
      nil
    end

    def complete_slot(pid, wait_result)
      slot_id = pid_to_slot.delete(pid)
      return unless slot_id

      slot = slots.delete(slot_id)
      return unless slot

      result = integration.build_result(wait_result, slot.log_paths)
      results << result
      progress_reporter&.progress(slot.mutant, scenario_result: result)
    end

    # Per-slot timeout check. Must be called after reap_all_completed_children
    # so that naturally-exited processes are already removed from slots.
    def check_timeouts
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      slots.each_value do |slot|
        next if slot.draining
        next unless now >= slot.started_at_monotonic + slot.timeout

        # Final targeted reap: if the child already exited, classify it normally.
        pid, status = Process.wait2(slot.pid, Process::WNOHANG)
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
    def drain_draining_slots
      draining = slots.select { |_, slot| slot.draining }
      return if draining.empty?

      broadcast_term(draining)
      IO.select(nil, nil, nil, PROCESS_DRAIN_WINDOW)
      draining.each_value { |slot| signal_process_group(slot.pid, :SIGKILL) }
      reap_and_remove_draining(draining)
    end

    def broadcast_term(draining)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      draining.each_value do |slot|
        slot.term_sent_at_monotonic = now
        signal_process_group(slot.pid, :SIGTERM)
      end
    end

    def reap_and_remove_draining(draining)
      draining.each_value do |slot|
        reap_pid(slot.pid)
        build_forced_result(slot)
        pid_to_slot.delete(slot.pid)
        slots.delete(slot.slot_id)
      end
    end

    def signal_process_group(pid, signal)
      Process.kill(signal, -pid)
    rescue Errno::ESRCH
      nil
    rescue Errno::EPERM
      # Process group not yet established; fall back to signalling the pid.
      begin
        Process.kill(signal, pid)
      rescue Errno::ESRCH
        nil
      end
    end

    def reap_pid(pid)
      Process.wait(pid)
    rescue Errno::ECHILD, Errno::ESRCH
      nil
    end

    def build_forced_result(slot)
      result = integration.build_result(:timeout, slot.log_paths)
      results << result
      progress_reporter&.progress(slot.mutant, scenario_result: result)
    end

    def resolve_test_files(mutant)
      if @options.key?(:test_files)
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
