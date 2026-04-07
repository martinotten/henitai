# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Removes individual links from a method chain by replacing the outer
    # send node with its receiver.
    #
    # Only fires when the immediate receiver is itself a :send node, which
    # naturally excludes block-receiver chains (list.select { }.count) and
    # standalone calls.
    #
    # Example: array.uniq.sort.first
    #   → array.uniq.sort  (removed .first)
    #   → array.uniq       (removed .sort)
    #   → array            (removed .uniq) — via the :uniq node
    class MethodChainUnwrap < Henitai::Operator
      NODE_TYPES = %i[send].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        receiver = node.children[0]
        return [] unless receiver.is_a?(Parser::AST::Node) && receiver.type == :send

        method_name = node.children[1]
        [
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: receiver,
            description: "removed .#{method_name} from chain"
          )
        ]
      end
    end
  end
end
