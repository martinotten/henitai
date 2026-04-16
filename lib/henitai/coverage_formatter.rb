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
      @collector.record_test(notification.example.metadata[:file_path])
    end

    def dump_summary(_summary)
      @collector.write_report
    end
  end
end
