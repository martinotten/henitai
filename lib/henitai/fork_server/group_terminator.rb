# frozen_string_literal: true

module Henitai
  module ForkServer
    # Stops a mutant process of the fork server and everything it started.
    #
    # The process is the server's child, not ours: waiting on it raises
    # ECHILD, so liveness is probed with signal 0 instead.
    class GroupTerminator
      GRACE_SECONDS = 2.0
      KILL_SECONDS = 1.0
      POLL_SECONDS = 0.02

      def initialize(killer: GroupKiller, clock: Process.method(:clock_gettime), pauser: Kernel.method(:sleep))
        @killer = killer
        @clock = clock
        @pauser = pauser
      end

      # @param leader [Boolean] false when the process already ended and only
      #   members of its group are left
      def terminate(pid, leader: true)
        @killer.kill(pid, :SIGTERM, leader:)
        return if gone_within?(pid, GRACE_SECONDS, leader)

        @killer.kill(pid, :SIGKILL, leader:)
        gone_within?(pid, KILL_SECONDS, leader)
      end

      private

      def gone_within?(pid, seconds, leader)
        deadline = now + seconds
        while @killer.alive?(pid, leader:)
          return false if now >= deadline

          @pauser.call(POLL_SECONDS)
        end
        true
      end

      def now
        @clock.call(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
