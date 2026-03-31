# frozen_string_literal: true

require "parser/current"
require_relative "source_parser"

module Henitai
  # Traverses a subject's AST and asks operators to build mutants.
  class MutantGenerator
    def generate(subjects, operators)
      normalized_operators = normalize_operators(operators)

      Array(subjects).flat_map do |subject|
        generate_for_subject(subject, normalized_operators)
      end
    end

    private

    def normalize_operators(operators)
      Array(operators).map do |operator|
        operator.is_a?(Class) ? operator.new : operator
      end
    end

    def generate_for_subject(subject, operators)
      return [] unless subject.source_file && subject.source_range

      visitor = SubjectVisitor.new(subject, operators)
      visitor.process(SourceParser.parse_file(subject.source_file))
      visitor.mutants
    end

    # Depth-first pre-order AST visitor for a single subject.
    class SubjectVisitor < Parser::AST::Processor
      attr_reader :mutants

      def initialize(subject, operators)
        super()
        @subject = subject
        @mutants = []
        @operators_by_node_type = operators.each_with_object(
          Hash.new { |hash, key| hash[key] = [] }
        ) do |operator, map|
          operator.class.node_types.each do |node_type|
            map[node_type] << operator
          end
        end
      end

      def handler_missing(node)
        return unless node_within_subject_range?(node)

        apply_operators(node)
        super
      end

      private

      def apply_operators(node)
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
