# frozen_string_literal: true

require_relative "stillborn_filter"

module Henitai
  # Validates that a mutant can be rendered and compiled as Ruby source.
  class SyntaxValidator
    def initialize
      @stillborn_filter = StillbornFilter.new
    end

    def valid?(mutant)
      !@stillborn_filter.suppressed?(mutant)
    end
  end
end
