# frozen_string_literal: true

require "forwardable"

module Henitai
  module ForkServer
    # Runs mutants through the fork server instead of booting the test
    # environment in every mutant process. Stands in for the integration of
    # the scheduler (ADR-20): #spawn_mutant hands it a handle for a process the
    # server forked, and #runtime lets it learn of that process's exit from
    # the server's events.
    #
    # Falls back to the integration's own per-mutant boot when the server is
    # lost, or when it cannot fork one particular mutant (for example the
    # control run's mutant, which the server never saw).
    class MutantRunner
      extend Forwardable

      def_delegators :@integration, :build_result, :select_tests, :test_files

      # @param fallback_timeout [#call, nil] test files -> timeout for a mutant
      #   the parent boots itself; the scheduler's timeout excludes boot while
      #   the server is active and would be far too short for it.
      # rubocop:disable Metrics/ParameterLists
      def initialize(integration:, client:, env: {}, warner: nil, fallback_timeout: nil,
                     report_store: Integration::ChildReportStore.new)
        # rubocop:enable Metrics/ParameterLists
        @integration = integration
        @client = client
        @env = env
        @warner = warner || ->(message) { Kernel.warn(message) }
        @fallback_timeout = fallback_timeout
        @report_store = report_store
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

      # Forks on the per-mutant path without asking the server, for a process
      # the server never saw (a control run, ADR-19). The pid is registered
      # with the runtime so the scheduler reaps it, and the timeout includes
      # booting the suite.
      # @return [Integration::ChildHandle]
      def spawn_local(mutant:, test_files:)
        spawn_locally(mutant, test_files)
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
