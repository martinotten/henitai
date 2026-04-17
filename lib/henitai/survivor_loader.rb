# frozen_string_literal: true

require "json"

module Henitai
  # Reads a Stryker-compatible mutation report and extracts the stable IDs
  # of mutants whose status is "Survived".
  class SurvivorLoader
    class FileNotFoundError < StandardError
    end

    class InvalidReportError < StandardError
    end

    class ScopeMismatchError < StandardError
    end

    # @param path          [String]       path to a Stryker-compatible JSON report
    # @param include_paths [Array<String>] from config.includes; used for scope validation
    def initialize(path, include_paths: [])
      @path          = path
      @include_paths = include_paths
    end

    def load
      raw    = read_file
      report = parse_json(raw)
      validate_scope(report)
      extract_survivor_ids(report)
    end

    private

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
      unless report.key?("schemaVersion")
        raise ScopeMismatchError,
              "Survivor report #{@path} is missing schemaVersion — is this a Henitai report?"
      end
      return if @include_paths.empty?

      report_files = report.fetch("files", {}).keys
      overlap = report_files.any? do |file|
        @include_paths.any? { |inc| file.start_with?(inc) }
      end
      return if overlap

      raise ScopeMismatchError,
            "Survivor report #{@path} has no file overlap with configured includes — " \
            "did you pass a report from a different project?"
    end

    def extract_survivor_ids(report)
      all_mutants(report).filter_map do |entry|
        unless entry["stableId"]
          warn "henitai: survivor report entry missing stableId — skipping"
          next
        end
        entry["stableId"] if entry["status"] == "Survived"
      end
    end

    def all_mutants(report)
      files = report.fetch("files", {})
      files.values.flat_map { |file_data| file_data.fetch("mutants", []) }
    end
  end
end
