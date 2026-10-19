# frozen_string_literal: true

module Henitai
  # Selects the test files to run for a mutant, coverage first.
  #
  # The per-test coverage map is the primary source: every integration test
  # file that provably reaches the mutant's lines is selected, whether or not
  # its name matches the subject. Name matching ({fallback}) is only consulted
  # when the map cannot decide — no map, no location, no covering test in the
  # map, or no covering test left in the integration. Over-selection costs
  # time; a missed covering test would produce a false survivor. Mutants on a
  # method's def line additionally take the name-matched tests, because that
  # line's coverage is only a load-time record.
  #
  # `test_files` and `fallback` are lambdas so that expensive name matching
  # and file discovery run only when they are needed.
  class PerTestCoverageSelector
    def initialize(coverage_report_reader: CoverageReportReader.new)
      @coverage_report_reader = coverage_report_reader
    end

    def select(mutant, reports_dir:, test_files:, fallback:)
      covering = per_test_coverage(reports_dir).tests_covering(mutant)
      return fallback.call if covering.empty?

      covered = covered_integration_tests(test_files.call, covering)
      return fallback.call if covered.empty?

      SignatureLine.on?(mutant) ? covered | fallback.call : covered
    end

    private

    def covered_integration_tests(integration_tests, covering)
      covering_paths = covering.map { |test| File.expand_path(test) }
      Array(integration_tests).select do |test|
        covering_paths.include?(File.expand_path(test))
      end
    end

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
