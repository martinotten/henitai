# frozen_string_literal: true

require "minitest"
require "henitai/test_file_outcomes"
require "henitai/minitest_result_file"

module Henitai
  module Integration
    # Records the outcome of each finished Minitest result per test file.
    class MinitestOutcomeReporter < ::Minitest::Reporter
      def initialize(outcomes, report_path: nil, io: $stdout)
        super(io, {})
        @outcomes = outcomes
        @report_path = report_path
      end

      def record(result)
        super
        MinitestResultFile.record(@outcomes, result)
      end

      def report
        super
        @outcomes.write(@report_path) if @report_path
      end
    end
  end
end
