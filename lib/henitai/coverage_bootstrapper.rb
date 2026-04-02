# frozen_string_literal: true

module Henitai
  # Ensures coverage data exists before the mutation pipeline starts.
  class CoverageBootstrapper
    def initialize(static_filter: StaticFilter.new)
      @static_filter = static_filter
    end

    def ensure!(source_files:, config:, integration:)
      return if source_files.empty?
      return if coverage_available?(source_files, config)

      bootstrap_coverage(integration)
      return if coverage_available?(source_files, config)

      raise CoverageError,
            "Coverage data is unavailable for the configured source files"
    end

    private

    attr_reader :static_filter

    def coverage_available?(source_files, config)
      coverage_lines = static_filter.coverage_lines_for(config)

      source_file_paths(source_files).any? do |path|
        Array(coverage_lines[path]).any?
      end
    end

    def source_file_paths(source_files)
      Array(source_files).map { |path| File.expand_path(path) }
    end

    def bootstrap_coverage(integration)
      # :survived means the full suite exited cleanly with no active mutant.
      return if integration.run_suite(integration.test_files) == :survived

      raise CoverageError, "Configured test suite failed while generating coverage"
    end
  end
end
