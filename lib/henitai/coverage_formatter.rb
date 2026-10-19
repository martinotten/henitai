# frozen_string_literal: true

require "henitai/per_test_coverage_collector"
require "henitai/test_file_outcomes"
require "henitai/rspec_outcomes"

module Henitai
  # Collects per-test coverage data for static filtering heuristics.
  class CoverageFormatter
    REPORT_DIR_ENV = PerTestCoverageCollector::REPORT_DIR_ENV
    REPORT_FILE_NAME = PerTestCoverageCollector::REPORT_FILE_NAME

    def initialize(_output, boot_clock: SuiteBootClock.from_env(ENV))
      @collector = PerTestCoverageCollector.new(boot_clock:)
      @outcomes = TestFileOutcomes.new
      @outcome_listener = RspecOutcomes::Listener.new(@outcomes)
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
      @outcome_listener.example_finished(notification)
    end

    def example_group_started(notification)
      @outcome_listener.example_group_started(notification)
    end

    def example_group_finished(notification)
      @outcome_listener.example_group_finished(notification)
    end

    def message(notification)
      @outcome_listener.message(notification)
    end

    def dump_summary(summary)
      @outcome_listener.dump_summary(summary)
      @collector.write_report
      @outcomes.write(TestFileOutcomes.default_report_path)
    end
  end
end
