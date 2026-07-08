# frozen_string_literal: true

module Henitai
  # Derives a per-mutant timeout from measured per-test-file durations.
  #
  # The calibrated value is `multiplier × sum(durations of the selected test
  # files)`, clamped to a floor so a near-instant baseline doesn't flag normal
  # jitter as a timeout. Returns nil — caller falls back to the static
  # default — when any selected test lacks timing data, so a partially
  # measured run is treated as uncalibratable rather than under-estimated.
  class TimeoutCalibrator
    FLOOR_SECONDS = 2.0

    # @param timing_source [#call] returns a Hash of test file path to
    #   wall-clock seconds; resolved lazily on first use.
    # @param multiplier [Numeric]
    def initialize(timing_source:, multiplier:)
      @timing_source = timing_source
      @multiplier = multiplier
    end

    # @param test_files [Array<String>]
    # @return [Float, nil]
    def timeout_for(test_files)
      files = Array(test_files)
      return nil if files.empty? || durations.empty?

      baselines = files.map { |file| durations[normalize(file)] }
      return nil if baselines.any?(&:nil?)

      [@multiplier * baselines.sum, FLOOR_SECONDS].max
    end

    private

    def durations
      @durations ||= (@timing_source.call || {}).transform_keys { |key| normalize(key) }
    end

    def normalize(path)
      File.expand_path(path.to_s)
    end
  end
end
