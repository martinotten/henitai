# frozen_string_literal: true

module Henitai
  class SlotScheduler
    # Decides whether a finished slot earns another attempt.
    #
    # The rule itself lives in FlakyRetryDecision; this class adds the shutdown
    # veto. A requested shutdown vetoes retries outright — respawning children
    # while tearing the run down would leak processes past the drain window.
    class RetryPolicy
      def initialize(max_retries:, flaky_tests: FlakyTestRegistry.new([]))
        @max_retries = max_retries.to_i
        @decision = FlakyRetryDecision.new(flaky_tests: flaky_tests, max_retries: @max_retries)
      end

      def retry?(slot:, result:, shutdown:)
        return false if shutdown || result.status != :killed

        @decision.retry?(status: :killed, killing_tests: result.killing_tests, attempts: slot.retry_count)
      end
    end
  end
end
