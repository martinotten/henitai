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

      bootstrap_coverage(integration, config)
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

    def bootstrap_coverage(integration, config)
      with_coverage_dir(config) do
        result = integration.run_suite(integration.test_files)
        return if result == :survived

        raise CoverageError, build_bootstrap_error(result)
      end
    end

    def build_bootstrap_error(result)
      return "Configured test suite failed while generating coverage" unless result.respond_to?(:log_path)

      tail = result.tail(12).strip
      message = +"Configured test suite failed while generating coverage"
      message << " (see #{result.log_path})"
      message << "\n#{tail}" unless tail.empty?
      message
    end

    def with_coverage_dir(config)
      original_coverage_dir = ENV.fetch("HENITAI_COVERAGE_DIR", nil)
      ENV["HENITAI_COVERAGE_DIR"] = coverage_dir(config)
      yield
    ensure
      if original_coverage_dir.nil?
        ENV.delete("HENITAI_COVERAGE_DIR")
      else
        ENV["HENITAI_COVERAGE_DIR"] = original_coverage_dir
      end
    end

    def coverage_dir(config)
      reports_dir = config.respond_to?(:reports_dir) ? config.reports_dir : nil
      return "coverage" if reports_dir.nil? || reports_dir.empty?

      File.join(reports_dir, "coverage")
    end
  end
end
