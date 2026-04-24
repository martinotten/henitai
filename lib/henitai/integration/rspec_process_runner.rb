# frozen_string_literal: true

module Henitai
  module Integration
    # Tracks real OS child pids for scheduler observability.
    # Gated on HENITAI_DEBUG_SCHEDULER=1. Thread-safe.
    module SchedulerDiagnostics
      @mutex = Mutex.new
      @intervals = []
      @live_count = 0
      @max_concurrent = 0

      class << self
        def enabled?
          ENV["HENITAI_DEBUG_SCHEDULER"] == "1"
        end

        def child_started(pid)
          return unless enabled?

          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @mutex.synchronize do
            @live_count += 1
            @max_concurrent = [@max_concurrent, @live_count].max
            @intervals << { pid: pid, started_at: started_at, ended_at: nil }
          end
        end

        def child_ended(pid)
          return if pid.nil? || !enabled?

          ended_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @mutex.synchronize do
            @live_count -= 1
            entry = @intervals.rfind { |i| i[:pid] == pid && i[:ended_at].nil? }
            entry[:ended_at] = ended_at if entry
          end
        end

        def summary
          @mutex.synchronize { { max_concurrent: @max_concurrent, intervals: @intervals.dup } }
        end

        def reset!
          @mutex.synchronize do
            @intervals = []
            @live_count = 0
            @max_concurrent = 0
          end
        end
      end
    end

    # Runs RSpec child and suite processes on behalf of the integration.
    class RspecProcessRunner
      ChildHandle = Struct.new(:pid, :log_paths)

      def run_mutant(integration, mutant:, test_files:, timeout:)
        handle = integration.spawn_mutant(mutant:, test_files:)
        SchedulerDiagnostics.child_started(handle.pid)
        wait_result = integration.wait_with_timeout(handle.pid, timeout)
        integration.build_result(wait_result, handle.log_paths)
      ensure
        SchedulerDiagnostics.child_ended(handle&.pid)
        finalize_mutant_run(integration, handle&.pid, wait_result)
      end

      def run_suite(integration, test_files, timeout:)
        log_paths = integration.scenario_log_paths("baseline")
        wait_result = nil
        FileUtils.mkdir_p(File.dirname(log_paths[:stdout_path]))
        pid = integration.spawn_suite_process(test_files, log_paths)
        wait_result = integration.wait_with_timeout(pid, timeout)
        integration.build_result(wait_result, log_paths)
      ensure
        if pid
          integration.cleanup_process_group(pid) unless wait_result == :timeout
          integration.reap_child(pid) if wait_result.nil?
        end
      end

      # Called from Integration::Rspec#spawn_mutant (and Minitest#spawn_mutant).
      # Forks a child, sets process group, activates the mutant, runs tests.
      # Returns a ChildHandle with the forked pid and log_paths.
      def spawn_mutant(integration, mutant:, test_files:, log_paths:)
        pid = Process.fork do
          Process.setpgid(0, 0)
          ENV["HENITAI_MUTANT_ID"] = mutant.id
          Process.exit(
            integration.run_in_child(
              mutant: mutant,
              test_files: test_files,
              log_paths: log_paths
            )
          )
        end
        ChildHandle.new(pid:, log_paths:)
      end

      private

      def finalize_mutant_run(integration, pid, wait_result)
        return unless pid

        integration.cleanup_process_group(pid) unless wait_result == :timeout
        integration.reap_child(pid) if wait_result.nil?
      end
    end
  end
end
