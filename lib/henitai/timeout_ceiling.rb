# frozen_string_literal: true

module Henitai
  # Applies the max_timeout ceiling to a calibrated timeout. The ceiling stops a
  # runaway mutant from running for minutes, but it must never push the timeout
  # below the measured test baseline, or every mutant would be reported as a
  # timeout instead of being tested.
  class TimeoutCeiling
    def initialize(ceiling:, warner:)
      @ceiling = ceiling
      @warner = warner
      @warned = false
    end

    def cap(calibrated, baseline)
      return calibrated if calibrated <= @ceiling

      warn_baseline_exceeds_ceiling(baseline) if baseline > @ceiling
      [@ceiling, baseline + TimeoutCalibrator::FLOOR_SECONDS].max
    end

    private

    def warn_baseline_exceeds_ceiling(baseline)
      return if @warned

      @warned = true
      @warner.call(
        format(
          "henitai: measured test baseline of %<baseline>.1fs exceeds max_timeout (%<ceiling>.1fs); " \
          "using %<timeout>.1fs instead",
          baseline:, ceiling: @ceiling, timeout: baseline + TimeoutCalibrator::FLOOR_SECONDS
        )
      )
    end
  end
end
