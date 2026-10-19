# frozen_string_literal: true

module Henitai
  # Re-runs a mutant whose kill is attributable only to known-flaky test files.
  #
  # Survivors are never retried: a retry could only turn a survivor into a
  # kill, which would inflate the score. A kill is retried only when every
  # killing test file is in the flaky set, up to `max_retries` times.
  class FlakyMutantRetrier
    attr_reader :retried_count

    def initialize(flaky_tests:, max_retries:)
      @decision = FlakyRetryDecision.new(flaky_tests: flaky_tests, max_retries: max_retries)
      @retried_count = 0
      @mutex = Mutex.new
    end

    def run(mutant:, integration:, test_files:, timeout:)
      result = integration.run_mutant(mutant: mutant, test_files: test_files, timeout: timeout)
      attempts = 0
      while @decision.retry?(**decision_input(result, attempts))
        attempts += 1
        result = integration.run_mutant(mutant: mutant, test_files: test_files, timeout: timeout)
      end
      @mutex.synchronize { @retried_count += 1 } if attempts.positive?
      result
    end

    private

    def decision_input(result, attempts)
      {
        status: status_of(result),
        killing_tests: result.respond_to?(:killing_tests) ? result.killing_tests : [],
        attempts: attempts
      }
    end

    def status_of(result)
      result.is_a?(Symbol) ? result : result.status
    end
  end
end
