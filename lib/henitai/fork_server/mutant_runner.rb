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

      # @param fallback_timeout [#call, nil] test files -> timeout for a mutant
      #   the parent boots itself; the timeout handed to #run_mutant excludes
      #   boot while the server is active and would be far too short for it.
      # rubocop:disable Metrics/ParameterLists
      def initialize(integration:, client:, env: {}, warner: nil, fallback_timeout: nil,
                     report_store: Integration::ChildReportStore.new, terminator: GroupTerminator.new)
        # rubocop:enable Metrics/ParameterLists
        @integration = integration
        @client = client
        @env = env
        @warner = warner || ->(message) { Kernel.warn(message) }
        @fallback_timeout = fallback_timeout
        @report_store = report_store
        @terminator = terminator
        @active = true
      end

      # False once the server is gone; a lost connection is noticed here even
      # when no request is pending.
      def active?
        deactivate("the fork server closed the connection") if @active && @client.lost?
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
        Integration::ChildHandle.new(pid: handle.pid, log_paths: handle.log_paths,
                                     timeout: fallback_timeout(test_files))
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
        @terminator.terminate(pid, leader: false) if pid && wait_result != :timeout
      end

      def wait_for(pid, timeout)
        status = @client.wait_exit(pid, timeout)
        return status if status

        @terminator.terminate(pid)
        @client.wait_exit(pid, EXIT_GRACE_SECONDS)
        @client.forget(pid)
        :timeout
      end

      def fallback(mutant, test_files, timeout)
        @integration.run_mutant(mutant:, test_files:, timeout: fallback_timeout(test_files) || timeout)
      end

      def fallback_timeout(test_files)
        @fallback_timeout&.call(test_files)
      end

      def deactivate(reason)
        return unless @active

        @active = false
        @client.abandon
        @warner.call("henitai: the fork server stopped (#{reason}); falling back to per-mutant boot")
      end
    end
  end
end
