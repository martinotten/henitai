# frozen_string_literal: true

require "json"

module Henitai
  # Applies static, pre-execution filtering to generated mutants.
  class StaticFilter
    DEFAULT_COVERAGE_REPORT_PATH = "coverage/.resultset.json"
    DEFAULT_PER_TEST_COVERAGE_REPORT_PATH = "coverage/henitai_per_test.json"

    # This method is the gate-level filter orchestrator.
    # rubocop:disable Metrics/MethodLength
    def apply(mutants, config)
      coverage_report_path = coverage_report_path(config)
      per_test_coverage_report_path = per_test_coverage_report_path(config)

      coverage_lines = coverage_lines_by_file(coverage_report_path)
      coverage_report_present = File.exist?(coverage_report_path)
      coverage_report_present ||= File.exist?(per_test_coverage_report_path)

      if coverage_lines.empty?
        coverage_lines = coverage_lines_from_test_lines(
          test_lines_by_file(per_test_coverage_report_path)
        )
      end

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
    # rubocop:enable Metrics/MethodLength

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
      File.expand_path(path)
    end

    def equivalence_detector
      @equivalence_detector ||= EquivalenceDetector.new
    end

    def coverage_report_path(_config)
      DEFAULT_COVERAGE_REPORT_PATH
    end

    def per_test_coverage_report_path(config)
      reports_dir = reports_dir_for(config)
      File.join(reports_dir, File.basename(DEFAULT_PER_TEST_COVERAGE_REPORT_PATH))
    end

    def reports_dir_for(config)
      return "coverage" unless config.respond_to?(:reports_dir)

      config.reports_dir || "coverage"
    end
  end
end
