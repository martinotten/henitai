# frozen_string_literal: true

require "henitai/per_test_coverage_collector"
require "henitai/test_file_outcomes"

module Henitai
  # Collects per-test coverage data for static filtering heuristics.
  class CoverageFormatter
    REPORT_DIR_ENV = PerTestCoverageCollector::REPORT_DIR_ENV
    REPORT_FILE_NAME = PerTestCoverageCollector::REPORT_FILE_NAME

    def initialize(_output, boot_clock: SuiteBootClock.from_env(ENV))
      @collector = PerTestCoverageCollector.new(boot_clock:)
      @outcomes = TestFileOutcomes.new
    end

    def example_started(_notification)
      @collector.test_started
    end

    def example_finished(notification)
      example = notification.example
      @collector.record_test(
        example.metadata[:file_path],
        duration: example.execution_result.run_time
      )
      @outcomes.record(example.metadata[:file_path], failed: example.execution_result.status == :failed)
    end

    def dump_summary(_summary)
      @collector.write_report
      @outcomes.write(TestFileOutcomes.default_report_path)
    end
  end
end
