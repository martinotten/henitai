# frozen_string_literal: true

module Henitai
  # Flat, single-threaded driver for parallel mutation runs.
  #
  # Owns the event loop and OS signal handling, and delegates the slot
  # lifecycle (spawning, reaping, timeout detection and the drain/broadcast
  # state machine) to a {SlotScheduler}. Because the scheduler is the sole
  # caller of Process.wait*, there are no races between threads reaping the
  # same child.
  class ProcessWorkerRunner
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

    # Loop primitives the {SlotScheduler} reads back from its host.
    attr_reader :worker_count, :runtime, :wakeup

    def initialize(worker_count:, runtime: Runtime.new, wakeup: nil)
      @worker_count = worker_count
      @runtime = runtime
      @wakeup = wakeup
      @shutdown_requested = false
    end

    # Number of mutants that required at least one retry during the run.
    # Mirrors the linear path's per-mutant flaky semantics so the engine can
    # report a single, mode-agnostic flaky statistic.
    def flaky_retry_count
      @scheduler ? @scheduler.flaky_retry_count : 0
    end

    # True once a graceful shutdown has been requested; read by the scheduler.
    def shutdown_requested?
      @shutdown_requested
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
      @scheduler.results
    ensure
      @wakeup&.close
      @wakeup = nil
    end

    private

    def prepare_run(mutants, integration, config, progress_reporter, options)
      @shutdown_requested = false
      @wakeup = Henitai::ProcessWakeup.new.install if @wakeup.nil?
      @scheduler = SlotScheduler.new(
        integration: integration,
        config: config,
        progress_reporter: progress_reporter,
        options: options,
        host: self
      )
      @scheduler.enqueue(mutants)
    end

    def event_loop
      saved_traps = install_signal_traps
      loop do
        break if @scheduler.done?

        break if process_cycle == :shutdown
      end
    ensure
      restore_signal_traps(saved_traps)
      raise Interrupt if @shutdown_requested
    end

    def process_cycle
      @scheduler.fill_idle_slots unless @shutdown_requested
      @scheduler.reap_all_completed_children
      @scheduler.check_timeouts
      @scheduler.fill_idle_slots unless @shutdown_requested
      return handle_shutdown if @shutdown_requested

      @scheduler.drain_draining_slots if @scheduler.draining_slots?
      @scheduler.fill_idle_slots unless @shutdown_requested
      return :done if @scheduler.done?

      wait_for_next_event
      nil
    end

    def handle_shutdown
      @scheduler.interrupt_active_slots
      @scheduler.drain_draining_slots
      :shutdown
    end

    def wait_for_next_event
      @wakeup&.wait(@scheduler.next_event_timeout)
      @wakeup&.drain
    end

    def install_signal_traps
      saved = {}
      %w[INT TERM HUP].each do |sig|
        saved[sig] = @runtime.trap(sig) { @shutdown_requested = true }
      end
      saved
    end

    def restore_signal_traps(saved)
      saved&.each { |sig, handler| @runtime.trap(sig, handler) }
    end
  end
end
