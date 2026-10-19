# frozen_string_literal: true

require "json"

module Henitai
  module ForkServer
    # Line-delimited JSON messages between the henitai parent and its fork
    # server. One message per line keeps both ends independent of how the
    # socket chunks the stream.
    #
    # Requests (parent -> server):
    #   run:      request_id, mutant_id, test_files, log_paths, env
    #   shutdown
    # Events (server -> parent):
    #   ready | boot_failed(reason)
    #   spawned(request_id, pid) | spawn_failed(request_id, reason)
    #   exited(pid, exitstatus | termsig)
    module Protocol
      MAX_READ_BYTES = 65_536

      def self.encode(message)
        "#{JSON.generate(message)}\n"
      end

      # Buffers a stream and yields whole messages. Returns nil at end of
      # stream, so a dead peer is distinguishable from a quiet one.
      class Reader
        TIMEOUT = :timeout

        def initialize(io)
          @io = io
          @buffer = +""
          @eof = false
        end

        # @param timeout [Float, nil] seconds to wait for a complete message
        # @return [Hash, Symbol, nil] the message, TIMEOUT, or nil at end of stream
        def next_message(timeout)
          deadline = timeout && (Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout)
          loop do
            line = @buffer.slice!(/\A.*\n/)
            return JSON.parse(line) if line
            return nil if @eof

            fill(deadline) or return TIMEOUT
          end
        end

        # True when a whole message is already read off the socket, so the
        # socket itself will not signal it as readable.
        def buffered_message?
          @buffer.include?("\n")
        end

        private

        def fill(deadline)
          remaining = deadline && [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max
          return false unless @io.wait_readable(remaining)

          chunk = @io.read_nonblock(MAX_READ_BYTES, exception: false)
          return true if chunk == :wait_readable

          @eof = true if chunk.nil?
          @buffer << chunk unless chunk.nil?
          true
        rescue EOFError, Errno::ECONNRESET
          @eof = true
        end
      end
    end
  end
end
