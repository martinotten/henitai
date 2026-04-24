# frozen_string_literal: true

module Henitai
  # Runs pending mutants across worker threads with signal and stdin handling.
  class ParallelExecutionRunner
    ParallelExecutionContext = Struct.new(
      :queue, :integration, :config, :progress_reporter,
      :mutex, :state, :old_handlers, :stdin_watcher
    )

    ChildInterval = Struct.new(:pid, :started_at, :ended_at)

    # Collects per-child timing data and tracks the peak concurrent live count.
    # Thread-safe via an internal mutex.
    class SchedulerDiagnostics
      def initialize
        @mutex = Mutex.new
        @intervals = []
        @live_count = 0
        @max_concurrent = 0
      end

      def child_started(pid)
        @mutex.synchronize do
          @live_count += 1
          @max_concurrent = @live_count if @live_count > @max_concurrent
          @intervals << ChildInterval.new(
            pid,
            Process.clock_gettime(Process::CLOCK_MONOTONIC),
            nil
          )
        end
      end

      def child_ended(pid)
        @mutex.synchronize do
          @live_count -= 1
          interval = @intervals.rfind { |i| i.pid == pid && i.ended_at.nil? }
          interval.ended_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) if interval
        end
      end

      def emit_summary
        @mutex.synchronize do
          warn "[henitai-scheduler] max_concurrent_children=#{@max_concurrent}"
          warn "[henitai-scheduler] child_intervals=#{@intervals.map(&:to_h)}"
        end
      end
    end

    def initialize(worker_count:)
      @worker_count = worker_count
    end

    def run(mutants, integration, config, progress_reporter, options = {})
      context = build_parallel_context(
        mutants,
        integration,
        config,
        progress_reporter
      )
      execute_parallel_execution(
        context,
        stdin_pipe: options.fetch(:stdin_pipe, false),
        process_mutant: options.fetch(:process_mutant)
      )
    end

    def execute_parallel_execution(context, stdin_pipe:, process_mutant:)
      diagnostics = build_diagnostics
      install_parallel_signal_traps(context)
      start_parallel_stdin_watcher(context, stdin_pipe)
      parallel_workers(context, process_mutant, diagnostics).each(&:join)
    ensure
      teardown_parallel_execution(context, diagnostics)
    end

    private

    attr_reader :worker_count

    def teardown_parallel_execution(context, diagnostics)
      stop_parallel_stdin_watcher(context)
      restore_parallel_signal_traps(context)
      diagnostics&.emit_summary
      raise context.state[:error] if context&.state&.fetch(:error, nil)
      raise Interrupt if context&.state&.fetch(:stopping, false)
    end

    def build_diagnostics
      SchedulerDiagnostics.new if debug_scheduler?
    end

    def debug_scheduler?
      ENV.fetch("HENITAI_DEBUG_SCHEDULER", nil) == "1"
    end

    def build_parallel_queue(mutants)
      Queue.new.tap { |queue| mutants.each { |mutant| queue << mutant } }
    end

    def build_parallel_context(mutants, integration, config, progress_reporter)
      ParallelExecutionContext.new(
        build_parallel_queue(mutants),
        integration,
        config,
        progress_reporter,
        Mutex.new,
        { stopping: false }
      )
    end

    def install_parallel_signal_traps(context)
      context.old_handlers = {
        int: trap(:INT) { stop_parallel_execution(context) },
        term: trap(:TERM) { stop_parallel_execution(context) },
        hup: trap(:HUP) { stop_parallel_execution(context) }
      }
    end

    def stop_parallel_execution(context)
      context.state[:stopping] = true
      context.queue.clear
    end

    def start_parallel_stdin_watcher(context, stdin_pipe)
      return unless stdin_pipe
      # CI runners expose stdin as a non-interactive pipe, so EOF there should
      # not be treated as a user disconnect.
      return if ci_environment?

      context.stdin_watcher = Thread.new do
        $stdin.read
        stop_parallel_execution(context)
      rescue IOError, Errno::EBADF
        nil
      end
    end

    def parallel_workers(context, process_mutant, diagnostics)
      Array.new(worker_count) do
        Thread.new { process_parallel_worker(context, process_mutant, diagnostics) }
      end
    end

    def process_parallel_worker(context, process_mutant, diagnostics)
      loop do
        break if context.state[:stopping]

        run_one_mutant(context, process_mutant, diagnostics)
      rescue ThreadError
        break
      rescue StandardError => e
        record_parallel_error(context, e)
        break
      end
    end

    def run_one_mutant(context, process_mutant, diagnostics)
      mutant = context.queue.pop(true)
      diagnostics&.child_started(mutant.object_id)
      process_mutant.call(
        mutant,
        context.integration,
        context.config,
        context.progress_reporter,
        context.mutex
      )
      diagnostics&.child_ended(mutant.object_id)
    end

    def stop_parallel_stdin_watcher(context)
      context&.stdin_watcher&.kill
    end

    def restore_parallel_signal_traps(context)
      handlers = context&.old_handlers
      return unless handlers

      trap(:INT, handlers[:int] || "DEFAULT")
      trap(:TERM, handlers[:term] || "DEFAULT")
      trap(:HUP, handlers[:hup] || "DEFAULT")
    end

    def record_parallel_error(context, error)
      context.mutex.synchronize do
        context.state[:error] ||= error
        context.state[:stopping] = true
        context.queue.clear
      end
    end

    def ci_environment?
      value = ENV.fetch("CI", nil)
      value && !%w[0 false].include?(value.downcase)
    end
  end
end
