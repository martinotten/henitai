# frozen_string_literal: true

require_relative "../fork_server"

module Henitai
  class ExecutionEngine
    # Opt-in fork-server execution (`mutation.fork_server`, ADR-15) for the
    # engine's linear path. While the block runs, @fork_server_runner (when a
    # server booted) runs the mutants; it is nil when the flag is off, the
    # integration cannot boot once, or the server failed to boot, and the
    # integration then boots per mutant.
    module ForkServerScope
      private

      def with_fork_server(mutants, integration, config)
        @fork_server_runner = start_fork_server(mutants, integration, config)
        yield
      ensure
        @fork_server_runner&.stop
        @fork_server_runner = nil
      end

      def start_fork_server(mutants, integration, config)
        return unless fork_server_requested?(config)
        return warn_fork_server_unsupported unless fork_server_supported?(integration)

        test_files = mutants.flat_map { |mutant| prioritized_tests_for(mutant, integration, config) }.uniq
        return if test_files.empty?

        ForkServer.start(integration:, mutants:, test_files:, log_path: fork_server_log_path(config))
      end

      def fork_server_requested?(config)
        config.respond_to?(:fork_server) && config.fork_server ? true : false
      end

      def fork_server_supported?(integration)
        integration.respond_to?(:fork_server_supported?) && integration.fork_server_supported?
      end

      def warn_fork_server_unsupported
        warn("henitai: mutation.fork_server is not supported for this integration; using per-mutant boot")
        nil
      end

      # The scheduler learns of served processes' exits through the server.
      def parallel_runtime_options
        @fork_server_runner&.active? ? { runtime: @fork_server_runner.runtime } : {}
      end

      def calibration_includes_boot?
        !@fork_server_runner&.active?
      end

      def fork_server_log_path(config)
        File.join(config.reports_dir, "mutation-logs", "fork-server.log")
      end
    end
  end
end
