# frozen_string_literal: true

require "unparser"

module Henitai
  # Suppresses mutants that do not produce syntactically valid Ruby.
  class StillbornFilter
    def suppressed?(mutant)
      source = render(mutant)
      return true unless source

      RubyVM::InstructionSequence.compile(wrapped_source(source))
      false
    rescue SyntaxError
      true
    end

    private

    def render(mutant)
      Unparser.unparse(mutant.mutated_node)
    rescue StandardError
      nil
    end

    def wrapped_source(source)
      <<~RUBY
        def __henitai_stillborn__
          #{source}
        end
      RUBY
    end
  end
end
