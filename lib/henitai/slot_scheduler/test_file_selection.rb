# frozen_string_literal: true

module Henitai
  class SlotScheduler
    # Resolves the test files a mutant should be run against.
    #
    # Three sources, in precedence order: a caller-supplied resolver lambda, a
    # fixed list, or the integration's own per-subject selection. The first two
    # exist so a survivor rerun or a per-test-coverage run can narrow the
    # selection without the integration knowing about it.
    #
    # Precedence is by key *presence*, not truthiness: an explicit empty list
    # means "no tests cover this", which the scheduler turns into
    # `:no_coverage`. Falling through to the integration there would silently
    # widen the selection back out.
    class TestFileSelection
      def initialize(options:, integration:)
        @options = options
        @integration = integration
      end

      def for(mutant)
        if @options.key?(:test_file_resolver)
          @options[:test_file_resolver].call(mutant)
        elsif @options.key?(:test_files)
          @options[:test_files]
        else
          @integration.select_tests(mutant.subject)
        end
      end

      # True when the resolver was asked and came back empty. Only meaningful
      # for a resolver-driven run: a fixed empty `test_files` list is a
      # deliberate "run nothing", not an absence of coverage.
      def resolved_empty?(test_files)
        @options.key?(:test_file_resolver) && test_files.empty?
      end
    end
  end
end
