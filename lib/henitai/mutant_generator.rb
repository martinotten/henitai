# frozen_string_literal: true

require_relative "parser_current"
require_relative "source_parser"

module Henitai
  # Traverses a subject's AST and asks operators to build mutants.
  class MutantGenerator
    def generate(subjects, operators, config: nil)
      normalized_operators = normalize_operators(operators)
      arid_node_filter = AridNodeFilter.new
      syntax_validator = SyntaxValidator.new
      sampling_strategy = SamplingStrategy.new

      mutants = Array(subjects).flat_map do |subject|
        generate_for_subject(
          subject,
          normalized_operators,
          config:,
          arid_node_filter:,
          syntax_validator:
        )
      end

      sample_mutants(mutants, config:, sampling_strategy:)
    end

    private

    def normalize_operators(operators)
      Array(operators).map do |operator|
        operator.is_a?(Class) ? operator.new : operator
      end
    end

    def generate_for_subject(subject, operators, config:, arid_node_filter:, syntax_validator:)
      return [] unless subject.source_file && subject.source_range

      visitor = SubjectVisitor.new(
        subject,
        operators,
        config:,
        arid_node_filter:,
        syntax_validator:
      )
      visitor.process(SourceParser.parse_file(subject.source_file))
      prune_mutants_per_line(
        visitor.mutants,
        max_mutants_per_line: config&.max_mutants_per_line || 1
      )
    end

    # Depth-first pre-order AST visitor for a single subject.
    class SubjectVisitor
      attr_reader :mutants

      def initialize(subject, operators, config:, arid_node_filter:, syntax_validator:)
        @subject = subject
        @config = config
        @mutants = []
        @arid_node_filter = arid_node_filter
        @syntax_validator = syntax_validator
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
          operator.mutate(node, subject: @subject).each do |mutant|
            @mutants << mutant if @syntax_validator.valid?(mutant)
          end
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

    def prune_mutants_per_line(mutants, max_mutants_per_line:)
      grouped = mutants.each_with_object({}) do |mutant, selected|
        key = line_key(mutant)
        selected[key] ||= []
        selected[key] << mutant
      end

      grouped.values.flat_map do |mutants_for_line|
        mutants_for_line.sort_by { |mutant| mutant_priority_key(mutant) }.take(max_mutants_per_line)
      end
    end

    def sample_mutants(mutants, config:, sampling_strategy:)
      sampling = config&.sampling
      return mutants unless sampling
      return mutants if sampling[:ratio].nil?

      sampling_strategy.sample(
        mutants,
        ratio: sampling[:ratio],
        strategy: sampling[:strategy] || :stratified
      )
    end

    def line_key(mutant)
      [
        mutant.location[:file],
        mutant.location[:start_line]
      ]
    end

    def mutant_priority_key(mutant)
      [
        operator_priority(mutant.operator),
        mutant.location[:start_col] || 0,
        mutant.description
      ]
    end

    def operator_priority(operator_name)
      operator_priority_map.fetch(operator_name, operator_priority_map.length)
    end

    def operator_priority_map
      # The constant order defines signal priority for per-line pruning.
      @operator_priority_map ||= Operator::FULL_SET.each_with_index.to_h
    end
  end
end
