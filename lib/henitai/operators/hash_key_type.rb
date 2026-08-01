# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Mutates symbol hash keys into string keys, one pair at a time
    # (`{ a: 1 }` -> `{ "a" => 1 }`). Symbol/string key confusion is a real
    # defect class, but frameworks that normalize keys (e.g. ActiveRecord's
    # `order`/`where`) make these mutants frequently unkillable — hence the
    # hard set, not full (ADR-12).
    class HashKeyType < Henitai::Operator
      NODE_TYPES = [:hash].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
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

      private

      def symbol_key_pair?(node)
        node.type == :pair && node.children.first&.type == :sym
      end

      def mutated_hash(node, index)
        pairs = node.children.each_with_index.map do |pair, pair_index|
          pair_index == index ? stringified_pair(pair) : pair
        end
        Parser::AST::Node.new(:hash, pairs)
      end

      def stringified_pair(pair)
        key, value = pair.children
        string_key = Parser::AST::Node.new(:str, [key.children.first.to_s])
        Parser::AST::Node.new(:pair, [string_key, value])
      end
    end
  end
end
