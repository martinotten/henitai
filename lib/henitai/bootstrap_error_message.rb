# frozen_string_literal: true

module Henitai
  # Explains a failed baseline suite run, pointing at its log when one exists.
  module BootstrapErrorMessage
    GENERIC = "Configured test suite failed while generating coverage"

    module_function

    # +timeout+ is the limit (seconds) the baseline ran under; it is named in
    # the message when the run timed out.
    def build(result, timeout: nil)
      return GENERIC unless result.respond_to?(:log_path)

      tail = result.tail(12).strip
      message = +headline(result, timeout)
      message << " (see #{result.log_path})"
      message << "\n#{tail}" unless tail.empty?
      message
    end

    def headline(result, timeout)
      return GENERIC unless timed_out?(result)

      limit = timeout ? "#{format_seconds(timeout)} s" : "the time limit"
      "Configured test suite did not finish within #{limit} while generating coverage; " \
        "raise mutation.suite_timeout to allow more time"
    end

    def timed_out?(result)
      result.respond_to?(:status) && result.status == :timeout
    end

    def format_seconds(seconds)
      seconds.is_a?(Float) && seconds == seconds.floor ? seconds.to_i : seconds
    end
  end
end
