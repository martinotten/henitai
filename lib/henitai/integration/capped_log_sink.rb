# frozen_string_literal: true

module Henitai
  module Integration
    # Writes captured child output to a log file up to a byte cap, then
    # discards the overflow and leaves a single truncation marker behind.
    # Not interrupt-safe: the drain thread must be stopped cooperatively,
    # never killed mid-write.
    class CappedLogSink
      def initialize(file, cap)
        @file = file
        @cap = cap
        @written = 0
        @truncated = false
      end

      def write(chunk)
        return unless @written < @cap

        slice = chunk.byteslice(0, @cap - @written)
        @file.write(slice)
        @written += slice.bytesize
        write_truncation_marker if @written >= @cap && !@truncated
      end

      private

      def write_truncation_marker
        @file.write("\n[henitai] output truncated at #{@cap} bytes\n")
        @truncated = true
      end
    end
  end
end
