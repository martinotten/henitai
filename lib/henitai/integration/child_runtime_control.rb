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

      def debug_child_timeout_dump(pid)
        return unless debug_child?

        debug_child_puts("[henitai-debug-child] timeout_signal_sent pid=#{pid}")
        Process.kill(:USR1, pid)
        pause(0.2)
      rescue Errno::ESRCH
        nil
      end

      def install_debug_timeout_trap
        Signal.trap("USR1") { debug_child_thread_dump("timeout") }
      end

      def debug_child_thread_dump(reason)
        return unless debug_child?

        debug_child_puts("[henitai-debug-child] thread_dump reason=#{reason}")
        Thread.list.each_with_index do |thread, index|
          debug_child_puts(
            "[henitai-debug-child] thread index=#{index} id=#{thread.object_id} " \
            "status=#{thread.status.inspect}"
          )
          Array(thread.backtrace).each do |line|
            debug_child_puts("[henitai-debug-child]   #{line}")
          end
        end
      end
    end
  end
end
