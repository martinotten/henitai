# frozen_string_literal: true

module Henitai
  class SlotScheduler
    # Low-level bridge to the OS process and signal primitives.
    #
    # Every Process.wait*/kill call routes through +runtime+ so that the
    # scheduler remains the single caller of the process table. Mixed into
    # {SlotScheduler}; relies on its +runtime+ reader.
    module ProcessControl
      GROUP_POLL_INTERVAL = 0.02
      GROUP_POLL_COUNT = 10

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

      # Terminates whatever a finished child left behind in its process group
      # (daemons, grandchildren). Waits at most PROCESS_DRAIN_WINDOW for them to
      # exit on SIGTERM before escalating to SIGKILL.
      def tear_down_process_group(pid)
        signal_process_group(pid, :SIGTERM)
        return unless group_members_remain?(pid)

        signal_process_group(pid, :SIGKILL)
      end

      def group_members_remain?(pid)
        GROUP_POLL_COUNT.times do
          return false unless process_group_alive?(pid)

          runtime.pause(GROUP_POLL_INTERVAL)
        end
        process_group_alive?(pid)
      end

      # Signal 0 probes existence only. ESRCH means the group is empty; EPERM
      # means members exist but belong to someone else.
      def process_group_alive?(pid)
        runtime.kill(0, -pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def reap_pid(pid)
        runtime.wait(pid)
      rescue Errno::ECHILD, Errno::ESRCH
        nil
      end
    end
  end
end
