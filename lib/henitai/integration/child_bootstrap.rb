# frozen_string_literal: true

module Henitai
  module Integration
    # The first thing a forked mutant child does, before any test-framework
    # work begins.
    #
    # Extracted from the fork block so the sequence is named and unit-testable
    # without forking, and so both the RSpec and Minitest paths -- which share
    # MutantRunSupport#spawn_mutant -- get identical treatment.
    module ChildBootstrap
      # Signals the parent traps for its own shutdown (INT/TERM/HUP) and for
      # its event-loop wakeup (CHLD). A child that kept those handlers would
      # ignore the SIGTERM sent while draining it and could write into the
      # parent's wakeup pipe.
      INHERITED_TRAPS = %w[INT TERM HUP CHLD].freeze

      # @param parent_pid [Integer] captured in the parent *before* Process.fork.
      #   Reading Process.ppid here instead would race the very death the
      #   watchdog is looking for: a parent that dies between fork and this
      #   line leaves the child with ppid 1 as its baseline, making it look
      #   permanently healthy.
      def self.after_fork!(parent_pid:)
        # First, so that even a crash later in this method releases the
        # reports-directory lock rather than pinning it with an inherited fd.
        InheritedFdRegistry.close_all!
        INHERITED_TRAPS.each { |signal| Signal.trap(signal, "DEFAULT") }
        Process.setpgid(0, 0)
        OrphanWatchdog.start(parent_pid:)
        nil
      end
    end
  end
end
