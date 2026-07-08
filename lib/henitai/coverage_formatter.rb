# frozen_string_literal: true

require "henitai/per_test_coverage_collector"

module Henitai
  # Collects per-test coverage data for static filtering heuristics.
  class CoverageFormatter
    REPORT_DIR_ENV = PerTestCoverageCollector::REPORT_DIR_ENV
    REPORT_FILE_NAME = PerTestCoverageCollector::REPORT_FILE_NAME

    def initialize(_output)
      @collector = PerTestCoverageCollector.new
    end

    def example_finished(notification)
      example = notification.example
      @collector.record_test(
        example.metadata[:file_path],
        duration: example.execution_result.run_time
      )
    end

    def dump_summary(_summary)
      @collector.write_report
    end
  end
end
