# frozen_string_literal: true

module Henitai
  # Measures how long a baseline suite process spent before its first test
  # started. The parent passes its spawn wall-clock time through
  # STARTED_AT_ENV; the boot time covers loading helpers and spec files and
  # running before(:suite).
  class SuiteBootClock
    STARTED_AT_ENV = "HENITAI_SUITE_STARTED_AT"

    # @param started_at [Float, nil] epoch seconds of the suite spawn
    # @param clock [#call] returns the current epoch seconds
    def initialize(started_at:, clock: -> { Time.now.to_f })
      @started_at = started_at
      @clock = clock
      @boot_seconds = nil
    end

    # @param env [Hash] environment of the suite process
    # @return [SuiteBootClock]
    def self.from_env(env, clock: -> { Time.now.to_f })
      new(started_at: parse_timestamp(env[STARTED_AT_ENV]), clock:)
    end

    def self.parse_timestamp(value)
      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    # Records boot time at the first test start only; later calls are ignored.
    def mark_first_test_started
      return if @boot_seconds || @started_at.nil?

      @boot_seconds = [@clock.call - @started_at, 0.0].max
    end

    # @return [Float] boot seconds, 0.0 when unknown
    def boot_seconds
      @boot_seconds || 0.0
    end

    # @return [Boolean] true once a boot time has been recorded
    def measured?
      !@boot_seconds.nil?
    end
  end
end
