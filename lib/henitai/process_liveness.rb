# frozen_string_literal: true

module Henitai
  # Answers whether a process id is still running.
  #
  # Extracted so the one subtle rule here lives in a single place: EPERM means
  # the process exists but belongs to someone else, so it counts as *alive*.
  # Only ESRCH proves it is gone. Getting that backwards would let
  # OrphanWatchdog kill live children, and would make the reports-directory
  # lock report a running owner as dead.
  module ProcessLiveness
    # @param pid [Integer, nil] process id to probe
    # @return [Boolean] false only when the pid provably does not exist
    def self.alive?(pid)
      return false unless pid.is_a?(Integer)

      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue StandardError
      # EPERM and anything unexpected: assume alive, the conservative answer
      # for every caller.
      true
    end
  end
end
