# frozen_string_literal: true

require_relative "coverage_report_reader"

module Henitai
  # Applies static, pre-execution filtering to generated mutants.
  class StaticFilter
    DEFAULT_COVERAGE_REPORT_PATH = CoverageReportReader::DEFAULT_COVERAGE_REPORT_PATH
    DEFAULT_PER_TEST_COVERAGE_REPORT_PATH = CoverageReportReader::DEFAULT_PER_TEST_COVERAGE_REPORT_PATH

    def initialize(coverage_report_reader: CoverageReportReader.new)
      @coverage_report_reader = coverage_report_reader
    end

    # This method is the gate-level filter orchestrator.
    def apply(mutants, config)
      coverage_lines = coverage_lines_for(config)
      coverage_report_present = coverage_report_present?(config)

      Array(mutants).each do |mutant|
        next if ignored_mutant?(mutant, config)

        mark_equivalent_mutant(mutant)
        mark_no_coverage_mutant(
          mutant,
          coverage_report_present:,
          coverage_lines:
        )
      end

      mutants
    end

    def coverage_lines_for(config)
      coverage_report_path = coverage_report_path(config)
      per_test_coverage_report_path = per_test_coverage_report_path(config)

      coverage_lines = coverage_lines_by_file(coverage_report_path)
      coverage_lines = merge_method_coverage(coverage_lines, coverage_report_path)
      return coverage_lines unless coverage_lines.empty?

      coverage_lines_from_test_lines(
        test_lines_by_file(per_test_coverage_report_path)
      )
    end

    def coverage_lines_by_file(path = DEFAULT_COVERAGE_REPORT_PATH)
      coverage_report_reader.coverage_lines_by_file(path)
    end

    def test_lines_by_file(path = DEFAULT_PER_TEST_COVERAGE_REPORT_PATH)
      coverage_report_reader.test_lines_by_file(path)
    end

    private

    attr_reader :coverage_report_reader

    def ignored?(mutant, config)
      source = source_for(mutant)
      return false unless source

      compiled_ignore_patterns(config).any? do |pattern|
        pattern.match?(source)
      end
    end

    def ignored_mutant?(mutant, config)
      return false unless ignored?(mutant, config)

      mutant.status = :ignored
      true
    end

    def mark_equivalent_mutant(mutant)
      return unless mutant.pending?

      equivalence_detector.analyze(mutant)
    end

    def mark_no_coverage_mutant(mutant, coverage_report_present:, coverage_lines:)
      return unless coverage_report_present
      return unless mutant.pending?
      return if covered?(mutant, coverage_lines)

      mutant.status = :no_coverage
    end

    def covered?(mutant, coverage_lines)
      file = normalize_path(mutant.location[:file])
      covered = Array(coverage_lines[file])
      (mutant.location[:start_line]..mutant.location[:end_line]).any? do |line|
        covered.include?(line)
      end
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

    def merge_method_coverage(coverage_lines, path)
      return coverage_lines unless File.exist?(path)

      JSON.parse(File.read(path)).each_value do |suite|
        suite.fetch("coverage", {}).each do |file, file_coverage|
          merge_file_method_coverage(coverage_lines, file, file_coverage)
        end
      end

      coverage_lines.transform_values(&:sort)
    end

    def merge_file_method_coverage(coverage_lines, file, file_coverage)
      methods = file_coverage["methods"]
      return unless methods.is_a?(Hash)

      normalized = normalize_path(file)
      methods.each do |key, count|
        next unless count.to_i.positive?

        range = method_line_range(key)
        next unless range

        coverage_lines[normalized] = Array(coverage_lines[normalized]) | range.to_a
      end
    end

    def method_line_range(key)
      m = key.match(/(\d+), \d+, (\d+), \d+\]\z/)
      return unless m

      (m.captures.first.to_i..m.captures.last.to_i)
    end

    def coverage_lines_from_test_lines(test_lines)
      coverage = Hash.new { |hash, key| hash[key] = [] }

      test_lines.each_value do |source_coverage|
        next unless source_coverage.is_a?(Hash)

        source_coverage.each do |source_file, lines|
          coverage[normalize_path(source_file)].concat(Array(lines).grep(Integer))
        end
      end

      coverage.transform_values(&:uniq).transform_values(&:sort)
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

    def equivalence_detector
      @equivalence_detector ||= EquivalenceDetector.new
    end

    def coverage_report_path(config)
      File.join(coverage_dir_for(config), ".resultset.json")
    end

    def coverage_report_present?(config)
      coverage_report_path = coverage_report_path(config)
      per_test_coverage_report_path = per_test_coverage_report_path(config)

      File.exist?(coverage_report_path) || File.exist?(per_test_coverage_report_path)
    end

    def per_test_coverage_report_path(config)
      reports_dir = reports_dir_for(config)
      File.join(reports_dir, File.basename(DEFAULT_PER_TEST_COVERAGE_REPORT_PATH))
    end

    def coverage_dir_for(config)
      return "coverage" unless config.respond_to?(:reports_dir)
      return "coverage" if config.reports_dir.nil? || config.reports_dir.empty?

      File.join(config.reports_dir, "coverage")
    end

    def reports_dir_for(config)
      return "coverage" unless config.respond_to?(:reports_dir)

      config.reports_dir || "coverage"
    end
  end
end
