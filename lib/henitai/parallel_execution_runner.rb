# frozen_string_literal: true

module Henitai
  # Runs pending mutants across worker threads with signal and stdin handling.
  class ParallelExecutionRunner
    ParallelExecutionContext = Struct.new(
      :queue, :integration, :config, :progress_reporter,
      :mutex, :state, :old_handlers, :stdin_watcher
    )

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
      install_parallel_signal_traps(context)
      start_parallel_stdin_watcher(context, stdin_pipe)
      parallel_workers(context, process_mutant).each(&:join)
    ensure
      stop_parallel_stdin_watcher(context)
      restore_parallel_signal_traps(context)
      raise context.state[:error] if context&.state&.fetch(:error, nil)
      raise Interrupt if context&.state&.fetch(:stopping, false)
    end

    private

    attr_reader :worker_count

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

      context.stdin_watcher = Thread.new do
        $stdin.read
        stop_parallel_execution(context)
      rescue IOError, Errno::EBADF
        nil
      end
    end

    def parallel_workers(context, process_mutant)
      Array.new(worker_count) { Thread.new { process_parallel_worker(context, process_mutant) } }
    end

    def process_parallel_worker(context, process_mutant)
      loop do
        break if context.state[:stopping]

        process_mutant.call(
          context.queue.pop(true),
          context.integration,
          context.config,
          context.progress_reporter,
          context.mutex
        )
      rescue ThreadError
        break
      rescue StandardError => e
        record_parallel_error(context, e)
        break
      end
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
  end
end
