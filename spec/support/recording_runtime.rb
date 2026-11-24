# frozen_string_literal: true

module Henitai
  module SpecSupport
    # Process-free stand-in for {ProcessWorkerRunner::Runtime}. It records
    # every #kill and never signals anything. Children stay running (#wait2
    # returns nil), the clock stands still at +now+, and every process group is
    # already gone once SIGTERM was sent, so teardown never escalates.
    class RecordingRuntime
      # @return [Array<Array(Symbol/String/Integer, Integer)>] (signal, pid)
      #   pairs in call order
      attr_reader :kills

      def initialize(now: 1.0)
        @kills = []
        @now = now
      end

      def clock_gettime(_clock_id) = @now

      def wait2(_pid, _flags = nil) = nil

      def wait(_pid) = nil

      def pause(_seconds) = nil

      def trap(_signal, _handler = nil, &) = nil

      def kill(signal, pid)
        @kills << [signal, pid]
        raise Errno::ESRCH if signal == 0

        1
      end
    end
  end
end
