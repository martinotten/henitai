# frozen_string_literal: true

module Henitai
  # Reads whether a test run's output says that no example ran.
  #
  # Both texts are matched at the start of a line only, and only the last
  # summary line counts: failure output may quote either text, indented, from
  # the test source, and the tests themselves may print summaries of nested
  # runs before the run's own.
  module ExampleSummary
    NO_EXAMPLES_FOUND = /^No examples found\.$/
    SUMMARY = /^(\d+) examples?, \d+ failures?/

    module_function

    def none_ran?(output)
      text = output.to_s
      summaries = text.scan(SUMMARY)
      return NO_EXAMPLES_FOUND.match?(text) if summaries.empty?

      summaries.last == ["0"]
    end
  end
end
