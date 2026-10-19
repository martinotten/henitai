# frozen_string_literal: true

module Henitai
  module ForkServer
    # The process primitives {SlotScheduler} drives, for a parallel run whose
    # mutant processes belong to the fork server (ADR-15).
    #
    # The parent cannot wait on a grandchild, so a served pid completes when
    # the server relays its +exited+ event. A pid forked locally (the per-mutant
    # fallback) is waited on as usual. Signals go straight to the OS: every
    # mutant process leads its own process group.
    class Runtime
      WAIT_SECONDS = 5.0
      ANY_PID = -1

      # @param client [Client]
      # @param base [#clock_gettime, #wait2, #kill, #wait, #pause, #trap]
      def initialize(client:, base: ProcessWorkerRunner::Runtime.new)
        @client = client
        @base = base
        @served = []
        @local = []
      end

      def served(pid)
        @served << pid
      end

      def local(pid)
        @local << pid
      end

      # Sockets the event loop must wake on besides its signal pipe.
      def wakeup_ios
        @client.lost? ? [] : [@client.io]
      end

      # An event already read off the socket does not wake a select on it.
      def pending_events?
        @client.pending_events?
      end

      def wait2(pid, flags = nil)
        return any_exit(flags) if pid == ANY_PID
        return served_exit(pid) if @served.include?(pid)

        local_exit(pid, flags)
      end

      def wait(pid)
        return @base.wait(pid) unless @served.include?(pid)

        status = await_exit(pid)
        @served.delete(pid) if status
        status
      end

      # A served process leads no group until its bootstrap ran +setpgid+;
      # until then the signal goes to the process itself.
      def kill(signal, pid)
        @base.kill(signal, pid)
      rescue Errno::ESRCH
        raise unless pid.negative? && @served.include?(-pid)

        @base.kill(signal, -pid)
      end

      def clock_gettime(clock_id) = @base.clock_gettime(clock_id)
      def pause(seconds) = @base.pause(seconds)
      def trap(signal, handler = nil, &) = @base.trap(signal, handler, &)

      private

      def any_exit(flags)
        finished = @client.poll_any_exit
        if finished
          @served.delete(finished.first)
          return finished
        end

        @local.each do |pid|
          result = local_exit(pid, flags)
          return result if result
        end
        nil
      end

      def served_exit(pid)
        status = @client.poll_exit(pid)
        return nil unless status

        @served.delete(pid)
        [pid, status]
      end

      def local_exit(pid, flags)
        result = @base.wait2(pid, flags)
        @local.delete(pid) if result
        result
      end

      def await_exit(pid)
        @client.wait_exit(pid, WAIT_SECONDS)
      rescue Client::ServerLost
        @client.poll_exit(pid)
      end
    end
  end
end
