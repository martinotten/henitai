# frozen_string_literal: true

require "digest"
require "unparser"

module Henitai
  # Computes a stable, run-independent SHA256 identity for a mutant.
  #
  # The identity is derived from the mutant's semantic content — not its
  # session UUID — so it survives across runs even when line numbers shift.
  module MutantIdentity
    def self.stable_id(mutant)
      Digest::SHA256.hexdigest(identity_components(mutant).join("\0"))
    end

    def self.identity_components(mutant)
      [
        mutant.subject.expression,
        mutant.operator,
        mutant.description,
        mutant.location[:file],
        mutant.location[:start_line],
        mutant.location[:end_line],
        mutant.location[:start_col],
        mutant.location[:end_col],
        mutation_signature(mutant)
      ]
    end
    private_class_method :identity_components

    def self.mutation_signature(mutant)
      Unparser.unparse(mutant.mutated_node)
    rescue StandardError
      mutant.mutated_node.class.name
    end
    private_class_method :mutation_signature
  end
end
