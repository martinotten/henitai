# frozen_string_literal: true

require "parser/current"
require_relative "source_parser"

module Henitai
  # Traverses a subject's AST and asks operators to build mutants.
  class MutantGenerator
    def generate(subjects, operators, config: nil)
      normalized_operators = normalize_operators(operators)

      Array(subjects).flat_map do |subject|
        generate_for_subject(subject, normalized_operators, config:)
      end
    end

    private

    def normalize_operators(operators)
      Array(operators).map do |operator|
        operator.is_a?(Class) ? operator.new : operator
      end
    end

    def generate_for_subject(subject, operators, config:)
      return [] unless subject.source_file && subject.source_range

      visitor = SubjectVisitor.new(subject, operators, config:)
      visitor.process(SourceParser.parse_file(subject.source_file))
      visitor.mutants
    end

    # Depth-first pre-order AST visitor for a single subject.
    class SubjectVisitor
      attr_reader :mutants

      def initialize(subject, operators, config:)
        @subject = subject
        @config = config
        @mutants = []
        @arid_node_filter = AridNodeFilter.new
        @operators_by_node_type = operators.each_with_object(
          Hash.new { |hash, key| hash[key] = [] }
        ) do |operator, map|
          operator.class.node_types.each do |node_type|
            map[node_type] << operator
          end
        end
      end

      def process(node)
        walk(node)
      end

      private

      def walk(node)
        return unless node.is_a?(Parser::AST::Node)

        apply_operators(node) if node_within_subject_range?(node)
        node.children.each do |child|
          walk(child)
        end
      end

      def apply_operators(node)
        return if @arid_node_filter.suppressed?(node, @config)

        @operators_by_node_type[node.type].each do |operator|
          @mutants.concat(operator.mutate(node, subject: @subject))
        end
      end

      def node_within_subject_range?(node)
        location = node.location&.expression
        return true unless location && @subject.source_range

        node_range = location.line..location.last_line
        ranges_overlap?(node_range, @subject.source_range)
      end

      def ranges_overlap?(left, right)
        left.begin <= right.end && right.begin <= left.end
      end
    end
  end
end
