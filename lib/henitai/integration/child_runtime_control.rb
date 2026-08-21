# frozen_string_literal: true

require_relative "coverage_suppression"

module Henitai
  module Integration
    # Runtime controls applied inside the mutant child process: coverage
    # suppression and the diagnostic timeout/thread-dump signal handling.
    module ChildRuntimeControl
      private

      def suppress_simplecov!
        CoverageRuntimeSuppressors.suppress_simplecov!
      end

      def suppress_coverage!
        CoverageRuntimeSuppressors.suppress_coverage!
      end

      # Signalling, not logging: the thread dump itself is emitted by the
      # child's USR1 handler, so this only asks for it and gives the child a
      # moment to write before the caller tears the process group down.
      def debug_child_timeout_dump(pid)
        return unless child_debug_log.enabled?

        child_debug_log.timeout_signal_sent(pid)
        Process.kill(:USR1, pid)
        pause(0.2)
      rescue Errno::ESRCH
        nil
      end

      def install_debug_timeout_trap
        Signal.trap("USR1") { child_debug_log.thread_dump("timeout") }
      end
    end
  end
end
