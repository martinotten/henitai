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
    # Captured at load time, before any test double can replace
    # `Process.kill`. A `Method` object keeps pointing at the original
    # definition even after the singleton method is redefined, which is what
    # makes this immune to stubbing.
    #
    # This is not defensiveness for its own sake: a mutant child runs the host
    # project's own suite, and a spec in that suite stubbing `Process.kill` to
    # raise ESRCH made this answer "parent is dead" while the parent was very
    # much alive. OrphanWatchdog then exited the child, which the scheduler
    # recorded as CompileError. Observed on henitai's own dogfood run.
    KILL = Process.method(:kill)

    # @param pid [Integer, nil] process id to probe
    # @param kill [#call] signalling primitive; injected only by specs, which
    #   cannot reach {KILL} by stubbing and must not be able to
    # @return [Boolean] false only when the pid provably does not exist
    def self.alive?(pid, kill: KILL)
      return false unless pid.is_a?(Integer)

      kill.call(0, pid)
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
