# frozen_string_literal: true

require "henitai/test_file_outcomes"

module Henitai
  module Integration
    # Records the outcome of each finished RSpec example per spec file.
    #
    # Failures outside an example produce no failed example. A hook error in
    # `before(:context)` fails the group's examples, so it is attributed
    # already; an `after(:context)` error is announced as a message while its
    # group is open and is attributed to that group's file. Everything else
    # counted by `errors_outside_of_examples_count` (a spec file that fails to
    # load, `before(:suite)`) has no file and is recorded as unattributed.
    module RspecOutcomes
      EVENTS = %i[example_finished example_group_started example_group_finished message dump_summary].freeze
      HOOK_ERROR = "An error occurred in "

      # RSpec drops finished examples from its groups after a run, so
      # outcomes are collected as the reporter announces them.
      class Listener
        def initialize(outcomes)
          @outcomes = outcomes
          @open_group_files = []
          @attributed_errors = 0
        end

        def example_finished(notification)
          RspecOutcomes.record(@outcomes, notification.example)
        end

        def example_group_started(notification)
          @open_group_files.push(RspecOutcomes.group_file(notification.group))
        end

        def example_group_finished(_notification)
          @open_group_files.pop
        end

        def message(notification)
          file = @open_group_files.last
          return unless file && notification.message.strip.start_with?(HOOK_ERROR)

          @outcomes.record(file, failed: true)
          @attributed_errors += 1
        end

        def dump_summary(summary)
          return unless summary.errors_outside_of_examples_count > @attributed_errors

          @outcomes.record_unattributed_failure
        end
      end

      module_function

      def register(outcomes, reporter)
        reporter.register_listener(Listener.new(outcomes), *EVENTS)
      end

      def group_file(group)
        metadata = group.metadata
        metadata[:absolute_file_path] || metadata[:file_path]
      end

      def record(outcomes, example)
        status = example.execution_result.status
        return if status.nil?

        outcomes.record(example.metadata[:file_path], failed: status == :failed)
      end
    end
  end
end
