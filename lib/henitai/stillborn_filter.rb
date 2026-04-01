# frozen_string_literal: true

require "unparser"

module Henitai
  # Suppresses mutants that do not produce syntactically valid Ruby.
  class StillbornFilter
    def suppressed?(mutant)
      RubyVM::InstructionSequence.compile(render(mutant))
      false
    rescue SyntaxError
      true
    end

    private

    def render(mutant)
      Unparser.unparse(mutant.mutated_node)
    end
  end
end
