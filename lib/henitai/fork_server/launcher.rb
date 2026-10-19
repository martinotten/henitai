# frozen_string_literal: true

module Henitai
  module ForkServer
    # Forks one mutant process from the booted server. The process then does
    # what a per-mutant child does after its own boot: process-group and trap
    # setup, output capture, activation, the tests, the child report.
    class Launcher
      # @param mutants [Hash{String => Mutant}] the run's mutants by id
      def initialize(integration:, mutants:, socket:, server_pid: Process.pid)
        @integration = integration
        @mutants = mutants
        @socket = socket
        @server_pid = server_pid
      end

      # @param request [Hash] a `run` request
      # @return [Integer] pid of the forked process
      def call(request)
        mutant = @mutants.fetch(request["mutant_id"]) { raise KeyError, "unknown mutant #{request['mutant_id']}" }
        test_files = Array(request["test_files"])
        log_paths = request.fetch("log_paths").transform_keys(&:to_sym)
        env = request["env"] || {}
        Process.fork { run_forked(mutant, test_files, log_paths, env) }
      end

      private

      def run_forked(mutant, test_files, log_paths, env)
        @socket.close
        Integration::ChildBootstrap.after_fork!(parent_pid: @server_pid)
        env.each { |key, value| ENV[key] = value }
        ENV["HENITAI_MUTANT_ID"] = mutant.id
        Process.exit(@integration.run_in_child(mutant:, test_files:, log_paths:))
      end
    end
  end
end
