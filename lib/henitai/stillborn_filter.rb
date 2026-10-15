# frozen_string_literal: true

require "prism"
require "unparser"

module Henitai
  # Suppresses mutants that do not produce syntactically valid Ruby.
  #
  # A mutant of a resolved method is checked in context: its activation
  # source -- the whole method with the mutation spliced in -- must parse. A
  # fragment such as `size: 2` (one keyword argument left) or a `next` guard
  # is only valid inside its call or block, so checking it on its own would
  # drop valid mutants. Without a method to splice into, the rendered
  # fragment is compiled inside a bare method instead.
  class StillbornFilter
    def suppressed?(mutant)
      activation = in_context_activation(mutant)
      return Prism.parse(activation.source).errors.any? if activation

      fragment_invalid?(mutant)
    end

    private

    def in_context_activation(mutant)
      return unless mutant.subject.respond_to?(:ast_node) && mutant.subject.ast_node

      Mutant::Activator.activation_for(mutant)
    end

    def fragment_invalid?(mutant)
      source = render(mutant)
      return true unless source

      RubyVM::InstructionSequence.compile(wrapped_source(source))
      false
    rescue SyntaxError
      true
    end

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
