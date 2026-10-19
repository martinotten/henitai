# frozen_string_literal: true

require "henitai/test_file_outcomes"

module Henitai
  module Integration
    # Records the outcome of each finished RSpec example per spec file.
    module RspecOutcomes
      # RSpec drops finished examples from its groups after a run, so
      # outcomes are collected as the reporter announces them.
      class Listener
        def initialize(outcomes)
          @outcomes = outcomes
        end

        def example_finished(notification)
          RspecOutcomes.record(@outcomes, notification.example)
        end
      end

      module_function

      def register(outcomes, reporter)
        reporter.register_listener(Listener.new(outcomes), :example_finished)
      end

      def record(outcomes, example)
        status = example.execution_result.status
        return if status.nil?

        outcomes.record(example.metadata[:file_path], failed: status == :failed)
      end
    end
  end
end
