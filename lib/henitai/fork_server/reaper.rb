# frozen_string_literal: true

module Henitai
  module ForkServer
    # Collects the processes that have ended since the last call, without
    # blocking. The fork server is the only process that can wait on its
    # mutant processes.
    module Reaper
      # @return [Array<Array(Integer, Status)>] pid and status per ended child
      def self.reap
        exits = [] # : Array[[Integer, Status]]
        loop do
          pid, status = Process.wait2(-1, Process::WNOHANG)
          break unless pid

          exits << [pid, Status.from_process_status(status)]
        end
        exits
      rescue Errno::ECHILD
        exits
      end
    end
  end
end
