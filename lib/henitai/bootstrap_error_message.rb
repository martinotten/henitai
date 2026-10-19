# frozen_string_literal: true

module Henitai
  # Explains a failed baseline suite run, pointing at its log when one exists.
  module BootstrapErrorMessage
    GENERIC = "Configured test suite failed while generating coverage"

    module_function

    def build(result)
      return GENERIC unless result.respond_to?(:log_path)

      tail = result.tail(12).strip
      message = +GENERIC
      message << " (see #{result.log_path})"
      message << "\n#{tail}" unless tail.empty?
      message
    end
  end
end
