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
        !shutdown && retry_wanted?(slot, result)
      end

      # True when only the shutdown stopped a retry: the kill may be faked by
      # a flaky test, so its verdict must not be cached (ADR-16).
      def vetoed?(slot:, result:, shutdown:)
        shutdown && retry_wanted?(slot, result)
      end

      private

      def retry_wanted?(slot, result)
        return false unless result.status == :killed

        @decision.retry?(status: :killed, killing_tests: result.killing_tests, attempts: slot.retry_count)
      end
    end
  end
end
