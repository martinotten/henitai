# frozen_string_literal: true

require "json"

module Henitai
  # Reads a Stryker-compatible mutation report and extracts survivor data.
  #
  # Returns a +Report+ value object carrying:
  #   - +survivor_ids+  — stable IDs of survived mutants
  #   - +coverage_map+  — stableId → [test_files] from prior coveredBy data
  #   - +git_sha+       — git HEAD at the time the report was written (may be nil)
  #
  # Scope validation is intentionally shallow: checks schemaVersion presence
  # and at least one file path overlap with config.includes.
  class SurvivorLoader
    # Value object returned by #load.
    Report = Struct.new(:survivor_ids, :coverage_map, :git_sha)

    class FileNotFoundError < StandardError; end
    class InvalidReportError < StandardError; end
    class ScopeMismatchError < StandardError; end

    # @param path          [String]        path to a Stryker-compatible JSON report
    # @param include_paths [Array<String>] from config.includes; used for scope validation
    def initialize(path, include_paths: [])
      @path          = path
      @include_paths = include_paths
    end

    # @return [Report]
    def load
      raw    = read_file
      report = parse_json(raw)
      validate_scope(report)
      build_report(report)
    end

    private

    def build_report(report)
      entries = known_entries(report)
      Report.new(
        survivor_ids: extract_survivor_ids(entries),
        coverage_map: extract_coverage_map(entries),
        git_sha: report["gitSha"]
      )
    end

    # Returns mutant entries that have a stableId, warning about those that don't.
    def known_entries(report)
      all_mutants(report).select do |entry|
        if entry["stableId"]
          true
        else
          warn "henitai: survivor report entry missing stableId — skipping"
          false
        end
      end
    end

    def extract_survivor_ids(entries)
      entries.filter_map { |e| e["stableId"] if e["status"] == "Survived" }
    end

    def extract_coverage_map(entries)
      entries.each_with_object({}) do |entry, map|
        covered = Array(entry["coveredBy"]).compact
        map[entry["stableId"]] = covered unless covered.empty?
      end
    end

    def read_file
      File.read(@path)
    rescue Errno::ENOENT
      raise FileNotFoundError, "Survivor report not found: #{@path}"
    end

    def parse_json(raw)
      JSON.parse(raw)
    rescue JSON::ParserError => e
      raise InvalidReportError, "Invalid JSON in survivor report #{@path}: #{e.message}"
    end

    def validate_scope(report)
      validate_schema_version!(report)
      return if @include_paths.empty?

      report_files = normalized_report_files(report)
      include_dirs_raw = normalized_include_dirs_raw
      include_dirs_abs = normalized_include_dirs_abs(include_dirs_raw)

      return if any_report_file_overlaps?(report_files, include_dirs_raw, include_dirs_abs)

      raise ScopeMismatchError,
            "Survivor report #{@path} has no file overlap with configured includes — " \
            "did you pass a report from a different project?"
    end

    def validate_schema_version!(report)
      return if report.key?("schemaVersion")

      raise ScopeMismatchError,
            "Survivor report #{@path} is missing schemaVersion — is this a Henitai report?"
    end

    def normalized_report_files(report)
      (report.fetch("files", {}) || {}).keys.map { |p| strip_trailing_slash(p.to_s) }
    end

    def normalized_include_dirs_raw
      @include_paths.map { |p| strip_trailing_slash(p.to_s) }.uniq
    end

    def normalized_include_dirs_abs(dirs_raw)
      dirs_raw.map { |p| File.expand_path(p) }.uniq
    end

    def strip_trailing_slash(path)
      path.sub(%r{/\z}, "")
    end

    def any_report_file_overlaps?(report_files, include_dirs_raw, include_dirs_abs)
      report_files.any? do |file|
        include_dirs_raw.any? { |inc| path_prefix_match?(file, inc) } ||
          include_dirs_abs.any? { |inc_abs| path_prefix_match?(File.expand_path(file), inc_abs) }
      end
    end

    def path_prefix_match?(path, dir)
      return false if path.empty? || dir.empty?

      path == dir || path.start_with?(dir + File::SEPARATOR)
    end

    def all_mutants(report)
      files = report.fetch("files", {}) || {}
      files.values.compact.flat_map { |file_data| file_data.fetch("mutants", []) }
    end
  end
end
