# frozen_string_literal: true

require "json"

module Henitai
  # Merges a scoped/partial run's Stryker schema into the previously-written
  # canonical report on disk instead of letting it fully replace the file.
  #
  # Pure and fail-safe: any anomaly (missing/corrupt prior file, mismatched
  # shape, a merge that would end up thinner than the current run alone)
  # falls back to the current run's schema by itself -- structurally never
  # worse than the unconditional overwrite this replaces.
  #
  # Merges at mutant granularity, keyed by `stableId`, not file granularity:
  # a `--survivors-from` rerun's schema only contains the re-verified
  # survivors for a file, so replacing that file's whole entry would drop
  # every other mutant (e.g. Killed ones) in the same file.
  module CanonicalReportMerger
    # @param prune_missing [Boolean] when true, prior file entries whose source
    #   file no longer exists on disk are dropped from the merged report (a
    #   deleted module, or one removed from `includes`). Off by default so the
    #   merge stays a pure schema operation; the reporter enables it because it
    #   runs from the project root where relative source paths resolve.
    def self.merge(current_schema, prior_path, prune_missing: false)
      current = stringify(current_schema)
      return current unless File.exist?(prior_path)

      prior = JSON.parse(File.read(prior_path))
      return current unless prior.is_a?(Hash) && prior["files"].is_a?(Hash)

      merged = merge_files(current, prior, prune_missing:)
      return current unless safe?(merged, current)

      merged
    rescue StandardError
      stringify(current_schema)
    end

    def self.merge_files(current, prior, prune_missing:)
      merged_files = overlay_current_mutants(deep_dup(prior["files"]), current)
      merged_files.reject! { |_, file| file["mutants"].empty? }
      prune_missing_source_files(merged_files) if prune_missing
      current.merge("files" => merged_files)
    end
    private_class_method :merge_files

    # Drops entries carried over from the prior report whose source file no
    # longer exists on disk (deleted module, or dropped from `includes`). Files
    # produced by the current run always exist, so a scoped rerun never removes
    # in-scope-but-untouched findings -- only genuinely gone paths.
    def self.prune_missing_source_files(merged_files)
      merged_files.select! { |file, _| File.exist?(file) }
    end
    private_class_method :prune_missing_source_files

    def self.overlay_current_mutants(merged_files, current)
      strip_rerun_mutants(merged_files, mutant_ids(current))
      append_current_mutants(merged_files, current)
      merged_files
    end
    private_class_method :overlay_current_mutants

    def self.strip_rerun_mutants(merged_files, current_ids)
      merged_files.each_value { |file| file["mutants"].reject! { |m| current_ids.include?(m["stableId"]) } }
    end
    private_class_method :strip_rerun_mutants

    def self.append_current_mutants(merged_files, current)
      current.fetch("files", {}).each do |file, entry|
        target = merged_files[file] ||= { "mutants" => [] }
        target["source"] = entry["source"]
        target["language"] = entry["language"]
        target["mutants"] += entry["mutants"]
      end
    end
    private_class_method :append_current_mutants

    def self.mutant_ids(schema)
      schema.fetch("files", {}).each_value.flat_map do |file|
        file.fetch("mutants", []).flat_map do |mutant|
          [mutant["stableId"], mutant["legacyStableId"]].compact
        end
      end.to_set
    end
    private_class_method :mutant_ids

    def self.safe?(merged, current)
      mutant_count(merged) >= mutant_count(current)
    end
    private_class_method :safe?

    def self.mutant_count(schema)
      schema.fetch("files", {}).values.sum { |file| file.fetch("mutants", []).size }
    end
    private_class_method :mutant_count

    def self.deep_dup(object)
      Marshal.load(Marshal.dump(object))
    end
    private_class_method :deep_dup

    def self.stringify(schema)
      JSON.parse(JSON.generate(schema))
    end
    private_class_method :stringify
  end
end
