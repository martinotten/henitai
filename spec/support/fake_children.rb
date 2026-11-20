# frozen_string_literal: true

module Henitai
  module SpecSupport
    # Process-free stand-in for forked mutant children, for specs that drive
    # the real {ProcessWorkerRunner} and {SlotScheduler}.
    #
    # It plays both sides of a child's life: #spawn hands out a fake pid (an
    # integration calls it from #spawn_mutant), and the object itself is the
    # runner's +runtime+: #wait2 reports every spawned pid as exited, in spawn
    # order. Process groups are always gone (kill 0 raises ESRCH), and the
    # clock stands still, so nothing times out.
    class FakeChildren
      ExitStatus = Struct.new(:exitstatus) do
        def success? = exitstatus.zero?
        def exited? = true
        def signaled? = false
        def termsig = nil
      end

      # @return [Array<Hash>] one entry per spawn: :pid, :mutant, :test_files,
      #   :worker_slot (HENITAI_WORKER_SLOT at spawn time)
      attr_reader :spawns, :traps

      def initialize
        @spawns = []
        @exited = []
        @traps = {}
        @next_pid = 40_000
      end

      # @return [Integration::ChildHandle] log_paths carry the pid, so a
      #   fake #build_result can find the spawn it belongs to
      def spawn(mutant, test_files, timeout: nil)
        pid = (@next_pid += 1)
        @spawns << { pid:, mutant:, test_files:, worker_slot: ENV.fetch(SlotScheduler::WORKER_SLOT_ENV, nil) }
        @exited << pid
        Integration::ChildHandle.new(pid:, log_paths: { pid: }, timeout:)
      end

      def spawn_for(log_paths) = @spawns.find { |spawn| spawn[:pid] == log_paths[:pid] }

      def clock_gettime(_clock_id) = 0.0

      def wait2(pid, _flags = nil)
        return nil if @exited.empty?

        exited = pid == -1 ? @exited.shift : @exited.delete(pid)
        exited && [exited, ExitStatus.new(0)]
      end

      def kill(signal, _pid)
        raise Errno::ESRCH if signal == 0

        1
      end

      def wait(_pid) = nil

      def pause(_seconds) = nil

      def trap(signal, handler = nil, &block)
        previous = @traps[signal]
        @traps[signal] = handler || block
        previous
      end
    end

    # Wakeup that never blocks, for a runner driven by {FakeChildren}.
    class FakeWakeup
      def install = self
      def watch = self
      def wait(_timeout) = nil
      def drain = nil
      def signal = nil
      def close = nil
    end
  end
end
