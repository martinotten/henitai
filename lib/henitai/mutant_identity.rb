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
      digest(identity_components(mutant))
    end

    # Stable id formula used before site offsets were introduced. Emitted as a
    # temporary report alias so scoped runs can replace pre-migration entries.
    def self.legacy_stable_id(mutant)
      digest(legacy_identity_components(mutant))
    end

    def self.identity_components(mutant)
      legacy_identity_components(mutant) + [site_offset(mutant)]
    end
    private_class_method :identity_components

    def self.legacy_identity_components(mutant)
      [
        mutant.subject.expression,
        mutant.operator,
        mutant.description,
        mutant.location[:file],
        mutation_signature(mutant)
      ]
    end
    private_class_method :legacy_identity_components

    def self.digest(components)
      Digest::SHA256.hexdigest(components.join("\0"))
    end
    private_class_method :digest

    # Position of the mutation site relative to its subject's own start,
    # not the file's absolute line/column — this still disambiguates two
    # call sites that produce the same operator/description/signature
    # within one subject (e.g. two `MethodExpression — replaced with nil`
    # mutants on different lines of a method), while surviving line drift
    # elsewhere in the file, which would shift absolute coordinates but
    # not this offset.
    def self.site_offset(mutant)
      subject_start = mutant.subject.source_range&.begin
      return mutant.location[:start_col].to_s unless subject_start

      "#{mutant.location[:start_line] - subject_start}:#{mutant.location[:start_col]}"
    end
    private_class_method :site_offset

    def self.mutation_signature(mutant)
      Unparser.unparse(mutant.mutated_node)
    rescue StandardError
      mutant.mutated_node.class.name
    end
    private_class_method :mutation_signature
  end
end
