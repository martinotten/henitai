# frozen_string_literal: true

module Henitai
  class SlotScheduler
    # Decides whether a finished slot earns another attempt.
    #
    # A survived verdict is the only retryable one: it is the verdict a flaky
    # test can fake, whereas a kill cannot be faked by flakiness. A requested
    # shutdown vetoes retries outright — respawning children while tearing the
    # run down would leak processes past the drain window.
    class RetryPolicy
      def initialize(max_retries:)
        @max_retries = max_retries.to_i
      end

      def retry?(slot:, result:, shutdown:)
        !shutdown && result.survived? && slot.retry_count < @max_retries
      end
    end
  end
end
