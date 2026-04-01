# frozen_string_literal: true

require "parser/current"

module Henitai
  module Operators
    # Reduces hash literals by emptying them or mutating symbol keys.
    class HashLiteral < Henitai::Operator
      NODE_TYPES = [:hash].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        return [] unless node.type == :hash
        return [] if node.children.empty?

        mutants = [empty_hash_mutant(node, subject:)]
        mutants.concat(symbol_key_mutants(node, subject:))
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

      def symbol_key_mutants(node, subject:)
        node.children.each_with_index.filter_map do |pair, index|
          next unless symbol_key_pair?(pair)

          build_mutant(
            subject:,
            original_node: node,
            mutated_node: mutated_hash(node, index),
            description: "replaced symbol key with string key"
          )
        end
      end

      def symbol_key_pair?(node)
        node.type == :pair && node.children.first&.type == :sym
      end

      def mutated_hash(node, pair_index)
        mutated_pairs = node.children.each_with_index.map do |pair, index|
          index == pair_index ? mutated_pair(pair) : pair
        end

        Parser::AST::Node.new(:hash, mutated_pairs)
      end

      def mutated_pair(pair)
        key, value = pair.children
        mutated_key = Parser::AST::Node.new(:str, [key.children.first.to_s])
        Parser::AST::Node.new(:pair, [mutated_key, value])
      end
    end
  end
end
