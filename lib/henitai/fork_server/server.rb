# frozen_string_literal: true

module Henitai
  module ForkServer
    # The request loop of the fork server process. It boots once (the boot
    # callable loads the integration environment), then forks one mutant
    # process per `run` request through the launcher and relays how each one
    # ended, because only this process can wait on them.
    class Server
      POLL_SECONDS = 0.5

      # @param socket [IO] the server end of the connection to the parent
      # @param boot [#call] loads the environment; raising reports `boot_failed`
      # @param launcher [#call] request Hash -> pid of the forked mutant process
      # @param reaper [#call] -> Array of [pid, Status] for ended children
      # @param wake_reader [IO, nil] readable when a child ended (CHLD wakeup)
      # @param killer [#call] pid -> kills that pid's process group
      # rubocop:disable Metrics/ParameterLists
      def initialize(socket:, boot:, launcher:, reaper: Reaper.method(:reap), wake_reader: nil,
                     killer: GroupKiller.method(:kill))
        # rubocop:enable Metrics/ParameterLists
        @socket = socket
        @reader = Protocol::Reader.new(socket)
        @boot = boot
        @launcher = launcher
        @reaper = reaper
        @wake_reader = wake_reader
        @killer = killer
        @live = []
        @shutdown = false
      end

      def serve
        return unless announce_boot

        until @shutdown
          wait_for_activity
          relay_exits
          handle_requests
        end
      ensure
        @live.each { |pid| @killer.call(pid) }
      end

      private

      def announce_boot
        @boot.call
        send_event("type" => "ready")
        true
      rescue StandardError, ScriptError, SystemExit => e
        send_event("type" => "boot_failed", "reason" => "#{e.class}: #{e.message}")
        false
      end

      def wait_for_activity
        ready = IO.select([@socket, @wake_reader].compact, nil, nil, POLL_SECONDS)
        drain_wake_reader if @wake_reader && ready&.first&.include?(@wake_reader)
      end

      def drain_wake_reader
        loop { @wake_reader.read_nonblock(4096) }
      rescue IO::WaitReadable, EOFError
        nil
      end

      def relay_exits
        @reaper.call.each do |pid, status|
          next unless @live.delete(pid)

          send_event({ "type" => "exited", "pid" => pid }.merge(status.to_event))
        end
      end

      def handle_requests
        loop do
          message = @reader.next_message(0)
          return @shutdown = true if message.nil?
          return unless message.is_a?(Hash)

          dispatch(message)
        end
      end

      def dispatch(message)
        case message["type"]
        when "run" then launch(message)
        when "shutdown" then @shutdown = true
        end
      end

      def launch(request)
        pid = @launcher.call(request)
        @live << pid
        send_event("type" => "spawned", "request_id" => request["request_id"], "pid" => pid)
      rescue StandardError => e
        send_event("type" => "spawn_failed", "request_id" => request["request_id"],
                   "reason" => "#{e.class}: #{e.message}")
      end

      def send_event(event)
        @socket.write(Protocol.encode(event))
      rescue IOError, SystemCallError
        @shutdown = true
      end
    end
  end
end
