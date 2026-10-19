# frozen_string_literal: true

require_relative "fork_server/protocol"
require_relative "fork_server/status"
require_relative "fork_server/reaper"
require_relative "fork_server/group_killer"
require_relative "fork_server/server"
require_relative "fork_server/launcher"
require_relative "fork_server/client"
require_relative "fork_server/runtime"
require_relative "fork_server/server_process"
require_relative "fork_server/mutant_runner"

module Henitai
  # Opt-in execution model (ADR-15): the test environment boots once in a
  # long-lived server process and every mutant process is forked from it.
  module ForkServer
    BOOT_TIMEOUT = 300.0

    # Starts a server for the run and returns a runner that sends mutants to
    # it, or nil, after a warning, when the server cannot be booted. The
    # caller then keeps the per-mutant boot.
    #
    # @return [MutantRunner, nil]
    # rubocop:disable Metrics/ParameterLists
    def self.start(integration:, mutants:, test_files:, log_path:, warner: nil, boot_timeout: BOOT_TIMEOUT)
      warner ||= ->(message) { Kernel.warn(message) }
      client = ServerProcess.start(integration:, mutants:, test_files:, log_path:)
      begin
        client.wait_until_ready(boot_timeout)
      rescue Client::BootFailed, Client::ServerLost => e
        client.shutdown
        warner.call("henitai: the fork server failed to boot (#{e.message}); see #{log_path}; " \
                    "falling back to per-mutant boot")
        return nil
      end
      MutantRunner.new(integration:, client:, warner:)
    end
    # rubocop:enable Metrics/ParameterLists
  end
end
