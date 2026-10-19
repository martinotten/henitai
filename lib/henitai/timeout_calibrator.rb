# frozen_string_literal: true

module Henitai
  # Derives a per-mutant timeout from measured per-test-file durations.
  #
  # The measured baseline is `sum(durations of the selected test files) +
  # boot seconds`, where boot covers loading helpers and spec files and
  # running before(:suite). The calibrated value is `multiplier × baseline`,
  # clamped to a floor so a near-instant baseline doesn't flag normal jitter
  # as a timeout. Returns nil — caller falls back to the static default —
  # when any selected test lacks timing data, so a partially measured run is
  # treated as uncalibratable rather than under-estimated.
  class TimeoutCalibrator
    FLOOR_SECONDS = 2.0

    # @param timing_source [#call] returns a Hash of test file path to
    #   wall-clock seconds; resolved lazily on first use.
    # @param multiplier [Numeric]
    # @param boot_seconds [#call] returns the measured suite boot time.
    # @param include_boot [Boolean] false when boot is paid once elsewhere
    #   (for example by a preloaded fork server) and must not be repeated.
    def initialize(timing_source:, multiplier:, boot_seconds: -> { 0.0 }, include_boot: true)
      @timing_source = timing_source
      @multiplier = multiplier
      @boot_seconds = boot_seconds
      @include_boot = include_boot
    end

    # @param test_files [Array<String>]
    # @return [Float, nil]
    def timeout_for(test_files)
      baseline = baseline_for(test_files)
      return nil if baseline.nil?

      [@multiplier * baseline, FLOOR_SECONDS].max
    end

    # @param test_files [Array<String>]
    # @return [Float, nil] measured baseline seconds, nil without timing data
    def baseline_for(test_files)
      files = Array(test_files)
      return nil if files.empty? || durations.empty?

      measured = files.map { |file| durations[normalize(file)] }
      return nil if measured.any?(&:nil?)

      measured.sum + boot_component
    end

    private

    def boot_component
      return 0.0 unless @include_boot

      @boot_component ||= @boot_seconds.call.to_f
    end

    def durations
      @durations ||= (@timing_source.call || {}).transform_keys { |key| normalize(key) }
    end

    def normalize(path)
      File.expand_path(path.to_s)
    end
  end
end
