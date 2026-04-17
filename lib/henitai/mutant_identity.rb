# frozen_string_literal: true

require "digest"
require "unparser"

module Henitai
  # Computes a stable, run-independent SHA256 identity for a mutant.
  #
  # The identity is derived from the mutant's semantic content, not the
  # session UUID or source coordinates, so it survives ordinary line shifts.
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
