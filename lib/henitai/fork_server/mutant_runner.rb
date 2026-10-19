# frozen_string_literal: true

require "forwardable"

module Henitai
  module ForkServer
    # Runs mutants through the fork server instead of booting the test
    # environment in every mutant process. Offers the integration's
    # #run_mutant, so the engine's retry and timeout logic is unchanged.
    #
    # Also stands in for the integration of a parallel run: #spawn_mutant hands
    # the scheduler a handle for a process the server forked, and #runtime lets
    # it learn of that process's exit from the server's events.
    #
    # Falls back to the integration's own per-mutant boot when the server is
    # lost, or when it cannot fork one particular mutant (for example the
    # control run's mutant, which the server never saw).
    class MutantRunner
      extend Forwardable

      EXIT_GRACE_SECONDS = 5.0

      def_delegators :@integration, :build_result, :select_tests, :test_files

      def initialize(integration:, client:, env: {}, warner: nil, report_store: Integration::ChildReportStore.new)
        @integration = integration
        @client = client
        @env = env
        @warner = warner || ->(message) { Kernel.warn(message) }
        @report_store = report_store
        @active = true
      end

      def active?
        @active
      end

      def runtime
        @runtime ||= Runtime.new(client: @client)
      end

      # @return [Integration::ChildHandle]
      def spawn_mutant(mutant:, test_files:)
        return spawn_locally(mutant, test_files) unless active?

        spawn_through_server(mutant, test_files)
      rescue Client::SpawnFailed
        spawn_locally(mutant, test_files)
      rescue Client::ServerLost => e
        deactivate(e.message)
        spawn_locally(mutant, test_files)
      end

      def run_mutant(mutant:, test_files:, timeout:)
        return fallback(mutant, test_files, timeout) unless active?

        run_through_server(mutant, test_files, timeout)
      rescue Client::SpawnFailed
        fallback(mutant, test_files, timeout)
      rescue Client::ServerLost => e
        deactivate(e.message)
        fallback(mutant, test_files, timeout)
      end

      def stop
        @active = false
        @client.shutdown
      end

      private

      def spawn_through_server(mutant, test_files)
        log_paths = @integration.mutant_log_paths(mutant)
        @report_store.clear(log_paths[:report_path])
        pid = @client.spawn_mutant(mutant_id: mutant.id, test_files:, log_paths:, env: spawn_env)
        runtime.served(pid)
        Integration::ChildHandle.new(pid:, log_paths:)
      end

      def spawn_locally(mutant, test_files)
        handle = @integration.spawn_mutant(mutant:, test_files:)
        runtime.local(handle.pid)
        handle
      end

      # The scheduler exports the slot of the process it is about to spawn.
      def spawn_env
        slot = ENV.fetch(SlotScheduler::WORKER_SLOT_ENV, nil)
        slot ? @env.merge(SlotScheduler::WORKER_SLOT_ENV => slot) : @env
      end

      def run_through_server(mutant, test_files, timeout)
        log_paths = @integration.mutant_log_paths(mutant)
        @report_store.clear(log_paths[:report_path])
        pid = @client.spawn_mutant(mutant_id: mutant.id, test_files:, log_paths:, env: @env)
        wait_result = wait_for(pid, timeout)
        @integration.build_result(wait_result, log_paths)
      ensure
        @integration.cleanup_process_group(pid) if pid && wait_result != :timeout
      end

      def wait_for(pid, timeout)
        status = @client.wait_exit(pid, timeout)
        return status if status

        @integration.cleanup_process_group(pid)
        @client.wait_exit(pid, EXIT_GRACE_SECONDS)
        :timeout
      end

      def fallback(mutant, test_files, timeout)
        @integration.run_mutant(mutant:, test_files:, timeout:)
      end

      def deactivate(reason)
        @active = false
        @warner.call("henitai: the fork server stopped (#{reason}); falling back to per-mutant boot")
      end
    end
  end
end
