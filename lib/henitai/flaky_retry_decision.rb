# frozen_string_literal: true

module Henitai
  # Decides whether a mutant verdict earns another attempt.
  #
  # Survivors are never retried: flakiness can only turn a survivor into a
  # kill, which would inflate the score. A kill is retried only when every test
  # that killed the mutant is a known flaky test, because flakiness can fake a
  # kill but not a survivor. Without a flaky set nothing is retried.
  class FlakyRetryDecision
    def initialize(flaky_tests:, max_retries:)
      @flaky_tests = flaky_tests
      @max_retries = max_retries.to_i
    end

    def retry?(status:, killing_tests:, attempts:)
      status == :killed &&
        attempts < @max_retries &&
        killing_tests.any? &&
        killing_tests.all? { |file| @flaky_tests.flaky?(file) }
    end
  end
end
