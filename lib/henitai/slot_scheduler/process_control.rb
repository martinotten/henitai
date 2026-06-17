# frozen_string_literal: true

module Henitai
  class SlotScheduler
    # Low-level bridge to the OS process and signal primitives.
    #
    # Every Process.wait*/kill call routes through +runtime+ so that the
    # scheduler remains the single caller of the process table. Mixed into
    # {SlotScheduler}; relies on its +runtime+ reader.
    module ProcessControl
      private

      def monotonic_time
        runtime.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def wnohang_reap(pid)
        runtime.wait2(pid, Process::WNOHANG)
      rescue Errno::ECHILD, Errno::ESRCH
        nil
      end

      def signal_process_group(pid, signal)
        runtime.kill(signal, -pid)
      rescue Errno::ESRCH
        nil
      rescue Errno::EPERM
        # Process group not yet established; fall back to signalling the pid.
        begin
          runtime.kill(signal, pid)
        rescue Errno::ESRCH
          nil
        end
      end

      def reap_pid(pid)
        runtime.wait(pid)
      rescue Errno::ECHILD, Errno::ESRCH
        nil
      end
    end
  end
end
