# frozen_string_literal: true

module Henitai
  module ForkServer
    # The parent's end of the connection to the fork server. It sends `run`
    # requests and collects the server's events; the parent cannot wait on the
    # mutant processes (they are the server's children), so their ends arrive
    # as `exited` events.
    class Client
      class ServerLost < StandardError; end

      class BootFailed < StandardError; end

      class SpawnFailed < StandardError; end

      SHUTDOWN_GRACE = 5.0
      SPAWN_TIMEOUT = 30.0
      REAP_POLL_SECONDS = 0.05

      # @param socket [IO] the parent end of the connection
      # @param pid [Integer, nil] the server process, reaped on #shutdown
      # @param shutdown_grace [Float] seconds the server may take to exit before it is killed
      def initialize(socket:, pid:, shutdown_grace: SHUTDOWN_GRACE)
        @socket = socket
        @pid = pid
        @shutdown_grace = shutdown_grace
        @reader = Protocol::Reader.new(socket)
        @next_request_id = 0
        @boot = nil
        @spawned = {}
        @exits = {}
        @outstanding = []
      end

      def lost?
        @lost == true
      end

      # The connection the parent can select on to learn of relayed events.
      def io
        @socket
      end

      # @raise [BootFailed] when the server reports failure or stays silent
      # @raise [ServerLost] when the server dies while booting
      def wait_until_ready(timeout)
        outcome = await(timeout) { @boot }
        raise BootFailed, "the fork server did not become ready within #{timeout}s" unless outcome
        raise BootFailed, outcome.last if outcome.first == :failed

        nil
      end

      # @return [Integer] pid of the forked mutant process
      # @raise [SpawnFailed] when the server could not fork this mutant
      # @raise [ServerLost]
      def spawn_mutant(mutant_id:, test_files:, log_paths:, env: {})
        request_id = (@next_request_id += 1)
        send_message("type" => "run", "request_id" => request_id, "mutant_id" => mutant_id,
                     "test_files" => test_files, "log_paths" => log_paths, "env" => env)
        outcome = await(SPAWN_TIMEOUT) { @spawned.delete(request_id) }
        lose_server("the fork server did not answer a run request") unless outcome
        raise SpawnFailed, outcome.last if outcome.first == :failed

        @outstanding << outcome.last
        outcome.last
      end

      # @return [Status, nil] how the process ended; nil when it is still
      #   running after +timeout+ seconds
      def wait_exit(pid, timeout)
        await(timeout) { @exits.delete(pid) }
      end

      # Non-blocking variants for the parallel scheduler, which reaps
      # completions from relayed events. A lost server completes every
      # outstanding process with a {Status.lost} instead of raising, so no
      # slot waits for an event that cannot arrive and no verdict is invented.
      #
      # @return [Status, nil]
      def poll_exit(pid)
        drain_available
        @exits.delete(pid)
      end

      # @return [Array(Integer, Status), nil]
      def poll_any_exit
        drain_available
        pid, status = @exits.first
        return nil unless pid

        @exits.delete(pid)
        [pid, status]
      end

      # Whether an event is already in user space (read off the socket but not
      # yet handed out), which the socket's readability no longer signals.
      def pending_events?
        !@exits.empty? || @reader.buffered_message?
      end

      # Stops tracking a pid whose result is no longer wanted, such as a child
      # the caller gave up on after a timeout. Its exit, if one already
      # arrived or arrives later, is dropped rather than left for a recycled pid.
      def forget(pid)
        drain_available
        @outstanding.delete(pid)
        @exits.delete(pid)
      end

      # Gives up on a server that is lost or stalled: it must not fork another
      # mutant that a local run is about to repeat.
      def abandon
        @lost = true
        kill_outstanding
        close_socket
        reap_server
        @pid = nil
      end

      def shutdown
        send_message("type" => "shutdown")
      rescue ServerLost
        nil
      ensure
        close_socket
        reap_server
      end

      private

      # The registry keeps fallback children from inheriting this connection.
      def close_socket
        InheritedFdRegistry.unregister(@socket)
        @socket.close unless @socket.closed?
      end

      # Without its server a mutant process has no one to reap it, and a local
      # rerun of the same mutant must not race it.
      def kill_outstanding
        @outstanding.each { |pid| GroupKiller.kill(pid) }
      end

      def await(timeout)
        deadline = now + timeout
        until (result = yield)
          remaining = deadline - now
          return nil unless remaining.positive?

          pump(remaining)
        end
        result
      end

      def pump(timeout)
        message = @reader.next_message(timeout)
        return if message == Protocol::Reader::TIMEOUT
        return lose_server if message.nil?

        record(message)
      end

      def drain_available
        loop do
          message = @reader.next_message(0)
          break if message == Protocol::Reader::TIMEOUT

          message.nil? ? lose_server : record(message)
        end
      rescue ServerLost
        nil
      end

      def lose_server(reason = "the fork server closed the connection")
        @lost = true
        kill_outstanding
        @outstanding.each { |pid| @exits[pid] ||= Status.lost }
        @outstanding.clear
        raise ServerLost, reason
      end

      def record(message)
        case message["type"]
        when "ready" then @boot = [:ready]
        when "boot_failed" then @boot = [:failed, message["reason"]]
        when "spawned" then @spawned[message["request_id"]] = [:ok, message["pid"]]
        when "spawn_failed" then @spawned[message["request_id"]] = [:failed, message["reason"]]
        when "exited" then record_exit(message)
        end
      end

      def record_exit(message)
        pid = message["pid"]
        return unless @outstanding.delete(pid)

        @exits[pid] = Status.from_event(message)
      end

      def send_message(message)
        @socket.write(Protocol.encode(message))
      rescue IOError, SystemCallError => e
        raise ServerLost, "the fork server connection is gone: #{e.message}"
      end

      def reap_server
        return if @pid.nil? || exited_within?(@shutdown_grace)

        Process.kill(:SIGKILL, @pid)
        Process.wait(@pid)
      rescue Errno::ECHILD, Errno::ESRCH
        nil
      end

      def exited_within?(grace)
        deadline = now + grace
        loop do
          return true if Process.wait(@pid, Process::WNOHANG)
          return false if now > deadline

          sleep(REAP_POLL_SECONDS)
        end
      rescue Errno::ECHILD
        true
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
