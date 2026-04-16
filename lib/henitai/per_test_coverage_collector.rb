# frozen_string_literal: true

require "coverage"
require "fileutils"
require "json"

module Henitai
  # Accumulates per-test line coverage deltas across test examples.
  #
  # Framework-agnostic core used by both the RSpec and Minitest adapters.
  # Callers invoke record_test after each test completes and write_report
  # once the full suite has finished.
  class PerTestCoverageCollector
    REPORT_DIR_ENV = "HENITAI_REPORTS_DIR"
    REPORT_FILE_NAME = "henitai_per_test.json"

    def initialize
      @coverage_by_test = Hash.new do |hash, test_file|
        hash[test_file] = Hash.new { |nested, source_file| nested[source_file] = [] }
      end
      @previous_snapshot = {}
      @warned_missing_coverage = false
    end

    def record_test(test_file)
      snapshot = current_snapshot
      return warn_missing_coverage unless snapshot

      new_lines(snapshot).each do |source_file, lines|
        @coverage_by_test[test_file][source_file].concat(lines)
        @coverage_by_test[test_file][source_file].uniq!
        @coverage_by_test[test_file][source_file].sort!
      end
      @previous_snapshot = snapshot
    end

    def write_report
      return if @coverage_by_test.empty?

      FileUtils.mkdir_p(File.dirname(report_path))
      File.write(report_path, JSON.pretty_generate(serializable_report))
    end

    private

    def report_path
      File.join(reports_dir, REPORT_FILE_NAME)
    end

    def reports_dir
      ENV.fetch(REPORT_DIR_ENV, "coverage")
    end

    def current_snapshot
      Coverage.peek_result
    rescue StandardError
      nil
    end

    def warn_missing_coverage
      return if @warned_missing_coverage

      warn "Per-test coverage unavailable; skipping coverage formatter output"
      @warned_missing_coverage = true
    end

    def new_lines(snapshot)
      snapshot.each_with_object({}) do |(source_file, file_coverage), result|
        next unless source_file?(source_file)

        lines = new_line_numbers(
          file_coverage,
          previous_line_counts(source_file)
        )
        result[source_file] = lines unless lines.empty?
      end
    end

    def new_line_numbers(file_coverage, previous_counts)
      line_counts_for(file_coverage).each_with_index.filter_map do |count, index|
        next unless count.to_i.positive?
        next if previous_counts.fetch(index, 0).to_i.positive?

        index + 1
      end
    end

    def previous_line_counts(source_file)
      line_counts_for(@previous_snapshot.fetch(source_file, []))
    end

    def line_counts_for(file_coverage)
      case file_coverage
      when Hash
        Array(file_coverage[:lines] || file_coverage["lines"])
      else
        Array(file_coverage)
      end
    end

    def source_file?(path)
      expanded = File.expand_path(path)
      prefix = "#{Dir.pwd}#{File::SEPARATOR}"
      return false unless expanded.start_with?(prefix)

      relative = expanded.sub(prefix, "")
      !relative.start_with?("spec#{File::SEPARATOR}") &&
        !relative.start_with?("test#{File::SEPARATOR}")
    end

    def serializable_report
      @coverage_by_test.transform_values do |source_map|
        source_map.to_h do |source_file, lines|
          [File.expand_path(source_file), lines.uniq.sort]
        end
      end
    end
  end
end
