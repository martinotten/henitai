# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Reduces hash literals: empties the whole hash and removes one pair at a
    # time. Symbol-key -> string-key mutation lives in {HashKeyType} (hard
    # set) because framework key normalization makes it frequently unkillable
    # (ADR-12).
    class HashLiteral < Henitai::Operator
      NODE_TYPES = [:hash].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        return [] if node.children.empty?

        mutants = [empty_hash_mutant(node, subject:)]
        mutants.concat(pair_removal_mutants(node, subject:))
        mutants
      end

      private

      def empty_hash_mutant(node, subject:)
        build_mutant(
          subject:,
          original_node: node,
          mutated_node: Parser::AST::Node.new(:hash, []),
          description: "replaced hash with empty hash"
        )
      end

      # Removing the only entry would duplicate the empty-hash mutant.
      def pair_removal_mutants(node, subject:)
        return [] if node.children.size < 2

        node.children.each_with_index.filter_map do |pair, index|
          next unless pair.type == :pair

          build_mutant(
            subject:,
            original_node: node,
            mutated_node: hash_without_pair(node, index),
            description: "removed hash pair #{pair_key_label(pair)}"
          )
        end
      end

      def hash_without_pair(node, pair_index)
        remaining = node.children.reject.with_index { |_pair, index| index == pair_index }
        Parser::AST::Node.new(:hash, remaining)
      end

      # Pair keys are always AST nodes (sym/str/…); their first child is the
      # literal value used purely as a human-readable label.
      def pair_key_label(pair)
        pair.children.first.children.first
      end
    end
  end
end
