# frozen_string_literal: true

require "minitest"
require "henitai/test_file_outcomes"

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
        file, = result.source_location
        return unless usable_source?(file)

        @outcomes.record(file, failed: !result.passed? && !result.skipped?)
      end

      def report
        super
        @outcomes.write(@report_path) if @report_path
      end

      private

      # Minitest reports no location for some results and "unknown" for others.
      def usable_source?(file)
        file.is_a?(String) && !file.empty? && file != "unknown"
      end
    end
  end
end
