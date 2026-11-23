# frozen_string_literal: true

require "minitest"
require "henitai/test_file_outcomes"
require "henitai/minitest_result_file"

module Henitai
  module Integration
    # Records the outcome of each finished Minitest result per test file.
    # +on_failure+ is called for every failing (not skipped) result.
    class MinitestOutcomeReporter < ::Minitest::Reporter
      def initialize(outcomes, report_path: nil, io: $stdout, on_failure: nil)
        super(io, {})
        @outcomes = outcomes
        @report_path = report_path
        @on_failure = on_failure
      end

      def record(result)
        super
        MinitestResultFile.record(@outcomes, result)
        @on_failure&.call if !result.passed? && !result.skipped?
      end

      def report
        super
        @outcomes.write(@report_path) if @report_path
      end
    end
  end
end
