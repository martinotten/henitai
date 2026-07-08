# frozen_string_literal: true

require "securerandom"
require_relative "mutant_identity"

module Henitai
  # Represents a single syntactic mutation applied to a Subject.
  #
  # A Mutant holds:
  #   - the original and mutated AST nodes
  #   - the operator that generated it
  #   - the source location of the mutation
  #   - its current status in the pipeline
  #
  # Statuses follow the Stryker mutation-testing-report-schema vocabulary:
  #   :pending, :killed, :survived, :timeout, :compile_error, :runtime_error,
  #   :ignored, :no_coverage
  class Mutant
    autoload :Activator, "henitai/mutant/activator"
    autoload :ParameterSource, "henitai/mutant/parameter_source"

    # Status-Vokabular folgt dem Stryker mutation-testing-report-schema.
    # :equivalent ist ein Henitai-interner Status (wird im JSON als "Ignored" serialisiert,
    # aber in der Scoring-Berechnung separat behandelt: confirmed equivalent mutants
    # werden aus dem Nenner der MS-Berechnung herausgenommen).
    STATUSES = %i[
      pending
      killed
      survived
      timeout
      compile_error
      runtime_error
      ignored
      no_coverage
      equivalent
    ].freeze

    attr_reader :id, :subject, :operator, :original_node, :mutated_node,
                :mutation_type, :description, :location,
                :precomputed_stable_id, :precomputed_activation_source
    attr_accessor :status, :killing_test, :duration, :covered_by, :tests_completed,
                  :ignore_reason, :from_cache

    # @param subject [Subject] the subject being mutated
    # @param operator [Symbol] operator name, e.g. :ArithmeticOperator
    # @param nodes [Hash] AST nodes with :original and :mutated entries
    # @param description [String] human-readable description of the mutation
    # @param location [Hash] { file:, start_line:, end_line:, start_col:, end_col: }
    # rubocop:disable Metrics/ParameterLists
    def initialize(subject:, operator:, nodes:, description:, location:,
                   precomputed_stable_id: nil, precomputed_activation_source: nil)
      @id            = SecureRandom.uuid
      @subject       = subject
      @operator      = operator
      @original_node = nodes.fetch(:original)
      @mutated_node  = nodes.fetch(:mutated)
      @description   = description
      @location      = location
      @precomputed_stable_id = precomputed_stable_id
      @precomputed_activation_source = precomputed_activation_source
      @status = :pending
      @killing_test = @duration = @covered_by = @tests_completed = @ignore_reason = nil
      @from_cache = false
    end
    # rubocop:enable Metrics/ParameterLists

    def stable_id
      @stable_id ||= @precomputed_stable_id || MutantIdentity.stable_id(self)
    end

    def killed?      = @status == :killed
    def from_cache?  = @from_cache == true
    def survived?    = @status == :survived
    def pending?     = @status == :pending
    def ignored?     = @status == :ignored
    def equivalent?  = @status == :equivalent

    def to_s
      "#{operator}@#{location[:file]}:#{location[:start_line]} — #{description}"
    end
  end
end
