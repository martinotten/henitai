# frozen_string_literal: true

module Henitai
  module Integration
    # Answers whether a test file has already been required, by matching it
    # against `$LOADED_FEATURES`.
    #
    # Both sides need normalizing: `$LOADED_FEATURES` holds absolute paths for
    # required files but callers hand over repository-relative test paths, and
    # either side may or may not carry the `.rb` suffix. A feature string that
    # cannot be expanded (invalid encoding, for instance) falls back to its raw
    # form rather than aborting the whole check — this runs inside a mutant
    # child whose only job is diagnostics.
    class LoadedFeatures
      def include?(file)
        candidates = candidates_for(file)
        $LOADED_FEATURES.any? do |feature|
          candidates.include?(feature) || candidates.include?(normalize(feature))
        end
      end

      def map(files) = files.map { |file| [file, include?(file)] }

      private

      def candidates_for(file)
        expanded = File.expand_path(file)
        [expanded, "#{expanded}.rb", file, "#{file}.rb"].uniq
      end

      def normalize(feature)
        File.expand_path(feature)
      rescue StandardError
        feature
      end
    end
  end
end
