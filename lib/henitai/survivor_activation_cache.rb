# frozen_string_literal: true

require "json"
require "fileutils"

module Henitai
  # Stores and retrieves pre-computed activations (see Mutant::Activation) for
  # survived mutants, enabling survivor reruns to skip the full mutant-generation
  # pipeline.
  #
  # The cache artifact (+activation-recipes.json+) is written alongside the
  # session snapshot in +reports/sessions/<session_id>/+. When a survivor rerun
  # finds this file next to the report it was given, it can build stub Mutant
  # objects directly and execute them without re-parsing source files.
  #
  # A recipe entry encodes everything needed to activate and re-report a mutant:
  # the activation (source, mode, file, line), subject coordinates, operator, description,
  # location, and the coveredBy test list.
  class SurvivorActivationCache
    FILENAME = "activation-recipes.json"

    # Build a recipe hash for each survived mutant that has a computable
    # activation source.
    #
    # @param survived_mutants [Array<Mutant>]
    # @return [Hash<String, Hash>] stableId → recipe
    def self.compute(survived_mutants)
      survived_mutants.each_with_object({}) do |mutant, cache|
        activation = Mutant::Activator.activation_for(mutant)
        next unless activation

        cache[mutant.stable_id] = build_recipe(mutant, activation)
      end
    end

    # @param path [String] path to +activation-recipes.json+
    # @return [Hash, nil] nil when the file is absent or unparseable
    def self.load(path)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end

    # @param path    [String]
    # @param recipes [Hash<String, Hash>]
    def self.write(path, recipes)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(recipes))
    end

    class << self
      private

      def build_recipe(mutant, activation)
        {
          "activation" => activation.to_h,
          "replacement" => mutant.mutated_source,
          **subject_fields(mutant.subject),
          "operator" => mutant.operator,
          "description" => mutant.description,
          "location" => serialize_location(mutant.location),
          "coveredBy" => Array(mutant.covered_by).compact
        }
      end

      def subject_fields(subject)
        {
          "namespace" => subject.namespace,
          "methodName" => subject.method_name,
          "methodType" => subject.method_type.to_s,
          "sourceFile" => subject.source_file
        }
      end

      def serialize_location(location)
        {
          "file" => location[:file],
          "startLine" => location[:start_line],
          "endLine" => location[:end_line],
          "startCol" => location[:start_col],
          "endCol" => location[:end_col]
        }.compact
      end
    end
  end
end
