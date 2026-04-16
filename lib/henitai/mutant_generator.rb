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
      source_node = source_node_for(subject)
      return [] unless source_node

      visitor = SubjectVisitor.new(
        subject,
        operators,
        config:,
        arid_node_filter:,
        syntax_validator:
      )
      visitor.process(source_node)
      visitor.mutants
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
        initialize_subject_range(subject)
        @operators_by_node_type = index_operators(operators)
      end

      def process(node)
        walk(node)
      end

      private

      def walk(node, parent: nil)
        return unless node.is_a?(Parser::AST::Node)

        # Str children of a non-heredoc dstr are raw text segments embedded
        # inside a quoted interpolated string. They have no surrounding quotes
        # in the source, so replacing them via source-fragment substitution
        # would insert a quoted literal into the raw-text position and produce
        # a SyntaxError when the mutant is activated.
        # Heredoc dstr children are exempt: the heredoc body is plain text, so
        # inserting "" there stays valid Ruby.
        return if embedded_non_heredoc_dstr_str?(node, parent)

        apply_operators(node) if node_within_subject_range?(node)
        node.children.each do |child|
          walk(child, parent: node)
        end
      end

      def embedded_non_heredoc_dstr_str?(node, parent)
        node.type == :str &&
          parent&.type == :dstr &&
          !heredoc_node?(parent)
      end

      def heredoc_node?(node)
        node.location.respond_to?(:heredoc_body) && node.location.heredoc_body
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
        return true unless @subject_range_begin

        location = node.location&.expression
        return true unless location

        location.line <= @subject_range_end && @subject_range_begin <= location.last_line
      end

      def initialize_subject_range(subject)
        subject_range = subject.source_range
        return unless subject_range

        @subject_range_begin = subject_range.begin
        @subject_range_end = subject_range.end
      end

      def index_operators(operators)
        operators.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |operator, map|
          operator.class.node_types.each do |node_type|
            map[node_type] << operator
          end
        end
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

    def source_node_for(subject)
      return subject.ast_node if subject.ast_node
      return nil unless subject.source_file && subject.source_range

      SourceParser.new.parse_file(subject.source_file)
    end
  end
end
