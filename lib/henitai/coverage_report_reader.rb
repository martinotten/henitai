# frozen_string_literal: true

require "json"

module Henitai
  # Reads coverage report formats used by Henitai.
  class CoverageReportReader
    DEFAULT_COVERAGE_REPORT_PATH = "coverage/.resultset.json"
    DEFAULT_PER_TEST_COVERAGE_REPORT_PATH = "coverage/henitai_per_test.json"

    def coverage_lines_by_file(path = DEFAULT_COVERAGE_REPORT_PATH)
      return {} unless File.exist?(path)

      coverage = Hash.new { |hash, key| hash[key] = [] }
      JSON.parse(File.read(path)).each_value do |result|
        result.fetch("coverage", {}).each do |file, file_coverage|
          coverage[normalize_path(file)].concat(covered_lines(file_coverage))
        end
      end

      coverage.transform_values(&:uniq).transform_values(&:sort)
    end

    def test_lines_by_file(path = DEFAULT_PER_TEST_COVERAGE_REPORT_PATH)
      return {} unless File.exist?(path)

      parsed = JSON.parse(File.read(path))
      return {} unless parsed.is_a?(Hash)

      parsed.transform_values do |coverage|
        normalize_test_coverage(coverage)
      end
    end

    private

    def covered_lines(file_coverage)
      Array(file_coverage["lines"]).each_with_index.filter_map do |count, index|
        index + 1 if count.to_i.positive?
      end
    end

    def normalize_test_coverage(coverage)
      case coverage
      when Hash
        coverage.transform_values do |lines|
          Array(lines).grep(Integer).uniq.sort
        end
      else
        Array(coverage).grep(Integer).uniq.sort
      end
    end

    def normalize_path(path)
      @normalize_path_cache ||= {}
      return @normalize_path_cache[path] if @normalize_path_cache.key?(path)

      expanded = File.expand_path(path)
      resolved = begin
        File.realpath(expanded)
      rescue Errno::ENOENT, Errno::ENOTDIR
        expanded
      end
      @normalize_path_cache[path] = resolved
    end
  end
end
