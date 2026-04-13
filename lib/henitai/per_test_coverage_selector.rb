# frozen_string_literal: true

module Henitai
  # Narrows candidate test files using the per-test coverage report.
  class PerTestCoverageSelector
    def initialize(coverage_report_reader: CoverageReportReader.new)
      @coverage_report_reader = coverage_report_reader
    end

    def filter(tests, mutant, reports_dir:)
      candidates = Array(tests)
      return candidates if candidates.empty?
      return candidates unless location_available?(mutant)
      return candidates unless per_test_coverage_available?(reports_dir)

      covered_tests = candidates.select do |test|
        covers_mutant?(test, mutant, reports_dir)
      end
      covered_tests.empty? ? candidates : covered_tests
    end

    private

    def location_available?(mutant)
      mutant.respond_to?(:location) &&
        mutant.location.is_a?(Hash) &&
        mutant.location[:file] &&
        mutant.location[:start_line] &&
        mutant.location[:end_line]
    end

    def covers_mutant?(test, mutant, reports_dir)
      covered_lines = coverage_lines_for(test, mutant, reports_dir)
      mutant_lines(mutant).any? { |line| covered_lines.include?(line) }
    end

    def coverage_lines_for(test, mutant, reports_dir)
      source_map = per_test_coverage(reports_dir)[test.to_s] || {}
      Array(source_map[File.expand_path(mutant.location[:file])]).uniq
    end

    def mutant_lines(mutant)
      (mutant.location[:start_line]..mutant.location[:end_line]).to_a
    end

    def per_test_coverage(reports_dir)
      @per_test_coverage ||= {}
      @per_test_coverage[reports_dir] ||= begin
        path = File.join(reports_dir, "henitai_per_test.json")
        coverage_report_reader.test_lines_by_file(path)
      end
    end

    def per_test_coverage_available?(reports_dir)
      !per_test_coverage(reports_dir).empty?
    end

    attr_reader :coverage_report_reader
  end
end
