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
  #
  # A mutant that removes the only assignment of a local which is read later
  # is suppressed as well (ACT-10): Ruby then parses the later read as a
  # method call, so the mutant would fail with a NameError wherever it runs
  # -- a trivial kill of a program other than the reported one.
  class StillbornFilter
    # Collects the names of identifiers Ruby parses as method calls.
    class VariableCalls < Prism::Visitor
      def self.tally(node)
        new.tap { |visitor| node.accept(visitor) }.names.tally
      end

      attr_reader :names

      def initialize
        super
        @names = []
      end

      def visit_call_node(node)
        @names << node.name if node.variable_call?
        super
      end
    end

    def initialize
      @original_calls = {}.compare_by_identity
    end

    def suppressed?(mutant)
      activation = in_context_activation(mutant)
      return fragment_invalid?(mutant) unless activation

      result = Prism.parse(activation.source)
      result.errors.any? || drops_local?(mutant.subject.ast_node, result.value)
    end

    private

    def drops_local?(method_node, activated)
      original = @original_calls[method_node] ||= original_calls(method_node)
      VariableCalls.tally(activated).any? do |name, count|
        count > original.fetch(name, 0) && local_read?(method_node, name)
      end
    end

    def original_calls(method_node)
      VariableCalls.tally(Prism.parse(method_node.location.expression.source).value)
    end

    def local_read?(node, name)
      return false unless node.is_a?(Parser::AST::Node)
      return true if node.type == :lvar && node.children.first == name

      node.children.any? { |child| local_read?(child, name) }
    end

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
