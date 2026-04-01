# frozen_string_literal: true

require "json"

module Henitai
  # Applies static, pre-execution filtering to generated mutants.
  class StaticFilter
    DEFAULT_COVERAGE_REPORT_PATH = "coverage/.resultset.json"
    DEFAULT_PER_TEST_COVERAGE_REPORT_PATH = "coverage/henitai_per_test.json"

    def apply(mutants, config)
      coverage_lines = coverage_lines_by_file
      coverage_report_present = File.exist?(DEFAULT_COVERAGE_REPORT_PATH)

      Array(mutants).each do |mutant|
        next if mark_ignored_mutant(mutant, config)

        next unless coverage_report_present

        mutant.status = :no_coverage unless covered?(mutant, coverage_lines)
      end

      mutants
    end

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

      parsed.transform_values { |lines| Array(lines).grep(Integer).uniq.sort }
    end

    private

    def ignored?(mutant, config)
      source = source_for(mutant)
      return false unless source

      compiled_ignore_patterns(config).any? do |pattern|
        pattern.match?(source)
      end
    end

    def mark_ignored_mutant(mutant, config)
      return unless ignored?(mutant, config)

      mutant.status = :ignored
      mutant
    end

    def covered?(mutant, coverage_lines)
      file = normalize_path(mutant.location[:file])
      start_line = mutant.location[:start_line]
      Array(coverage_lines[file]).include?(start_line)
    end

    def source_for(mutant)
      original_node = mutant.original_node
      location = original_node&.location
      expression = location&.expression
      expression&.source
    end

    def compiled_ignore_patterns(config)
      patterns = Array(config&.ignore_patterns).dup.freeze
      @compiled_ignore_patterns ||= {}
      @compiled_ignore_patterns[patterns] ||= patterns.map { |pattern| Regexp.new(pattern) }
    end

    def covered_lines(file_coverage)
      Array(file_coverage["lines"]).each_with_index.filter_map do |count, index|
        index + 1 if count.to_i.positive?
      end
    end

    def normalize_path(path)
      File.expand_path(path)
    end
  end
end
