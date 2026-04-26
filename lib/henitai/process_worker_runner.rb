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
