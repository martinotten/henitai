# frozen_string_literal: true

module Henitai
  # Read-side view of the per-test coverage map (henitai_per_test.json):
  # which test files reach which source lines. The single implementation of
  # the line-intersection check, shared by test selection
  # (PerTestCoverageSelector) and survivor verdict reuse (IncrementalFilter),
  # so both callers always agree on what "covers" means.
  class PerTestCoverage
    def initialize(reports_dir:, coverage_report_reader: CoverageReportReader.new)
      @reports_dir = reports_dir
      @coverage_report_reader = coverage_report_reader
    end

    def available?
      !map.empty?
    end

    # The full-map intersection set: every test file whose covered lines
    # intersect the mutant's current line range.
    #
    # @return [Array<String>] sorted test file paths; empty when the map or
    #   the mutant's location is unavailable — callers must treat that as
    #   "unknown", never as "not covered".
    def tests_covering(mutant)
      return [] unless location_available?(mutant)

      map.keys.select { |test| covers?(test, mutant) }.sort
    end

    # True when the given test file's recorded coverage intersects the
    # mutant's current line range.
    def covers?(test, mutant)
      return false unless location_available?(mutant)

      coverage_lines_for(test, mutant).intersect?(mutant_lines(mutant))
    end

    private

    attr_reader :reports_dir, :coverage_report_reader

    def location_available?(mutant)
      mutant.respond_to?(:location) &&
        mutant.location.is_a?(Hash) &&
        mutant.location[:file] &&
        mutant.location[:start_line] &&
        mutant.location[:end_line]
    end

    def coverage_lines_for(test, mutant)
      source_map = map[test.to_s] || {}
      Array(source_map[File.expand_path(mutant.location[:file])]).uniq
    end

    def mutant_lines(mutant)
      (mutant.location[:start_line]..mutant.location[:end_line]).to_a
    end

    def map
      @map ||= coverage_report_reader.test_lines_by_file(
        File.join(reports_dir, PerTestCoverageCollector::REPORT_FILE_NAME)
      )
    end
  end
end
