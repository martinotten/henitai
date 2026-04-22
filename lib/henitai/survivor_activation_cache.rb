# frozen_string_literal: true

require "json"
require "fileutils"

module Henitai
  # Stores and retrieves pre-computed +define_method+ activation sources for
  # survived mutants, enabling survivor reruns to skip the full mutant-generation
  # pipeline.
  #
  # The cache artifact (+activation-recipes.json+) is written alongside the
  # session snapshot in +reports/sessions/<session_id>/+. When a survivor rerun
  # finds this file next to the report it was given, it can build stub Mutant
  # objects directly and execute them without re-parsing source files.
  #
  # A recipe entry encodes everything needed to activate and re-report a mutant:
  # the +define_method+ source, subject coordinates, operator, description,
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
        source = Mutant::Activator.activation_source_for(mutant)
        next unless source

        cache[mutant.stable_id] = build_recipe(mutant, source)
      end
    end

    # @param path [String] path to +activation-recipes.json+
    # @return [Hash, nil] nil when the file is absent or unparseable
    def self.load(path)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError, Errno::ENOENT
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

      def build_recipe(mutant, activation_source)
        {
          "activationSource" => activation_source,
          "namespace" => mutant.subject.namespace,
          "methodName" => mutant.subject.method_name,
          "methodType" => mutant.subject.method_type.to_s,
          "sourceFile" => mutant.subject.source_file,
          "operator" => mutant.operator,
          "description" => mutant.description,
          "location" => serialize_location(mutant.location),
          "coveredBy" => Array(mutant.covered_by).compact
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
