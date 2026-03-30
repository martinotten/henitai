# frozen_string_literal: true

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
                :mutation_type, :description, :location
    attr_accessor :status, :killing_test, :duration

    # @param subject [Subject] the subject being mutated
    # @param operator [Symbol] operator name, e.g. :ArithmeticOperator
    # @param nodes [Hash] AST nodes with :original and :mutated entries
    # @param description [String] human-readable description of the mutation
    # @param location [Hash] { file:, start_line:, end_line:, start_col:, end_col: }
    def initialize(subject:, operator:, nodes:, description:, location:)
      @id            = SecureRandom.uuid
      @subject       = subject
      @operator      = operator
      @original_node = nodes.fetch(:original)
      @mutated_node  = nodes.fetch(:mutated)
      @description   = description
      @location      = location
      @status        = :pending
      @killing_test  = nil
      @duration      = nil
    end

    def killed?      = @status == :killed
    def survived?    = @status == :survived
    def pending?     = @status == :pending
    def ignored?     = @status == :ignored
    def equivalent?  = @status == :equivalent

    def to_s
      "#{operator}@#{location[:file]}:#{location[:start_line]} — #{description}"
    end
  end
end
