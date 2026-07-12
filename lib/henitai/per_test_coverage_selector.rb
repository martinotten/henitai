# frozen_string_literal: true

module Henitai
  # Narrows candidate test files using the per-test coverage report.
  #
  # The intersection check itself lives in {PerTestCoverage}; this class only
  # adds the selection policy: when no candidate provably covers the mutant
  # (or the map / location is unavailable), it falls back to all candidates —
  # over-selection costs time, never correctness.
  class PerTestCoverageSelector
    def initialize(coverage_report_reader: CoverageReportReader.new)
      @coverage_report_reader = coverage_report_reader
    end

    def filter(tests, mutant, reports_dir:)
      candidates = Array(tests)
      return candidates if candidates.empty?

      coverage = per_test_coverage(reports_dir)
      covered_tests = candidates.select do |test|
        coverage.covers?(test, mutant)
      end
      covered_tests.empty? ? candidates : covered_tests
    end

    private

    def per_test_coverage(reports_dir)
      @per_test_coverage ||= {}
      @per_test_coverage[reports_dir] ||= PerTestCoverage.new(
        reports_dir:,
        coverage_report_reader:
      )
    end

    attr_reader :coverage_report_reader
  end
end
