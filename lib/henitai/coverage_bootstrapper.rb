# frozen_string_literal: true

module Henitai
  # Ensures coverage data exists before the mutation pipeline starts.
  class CoverageBootstrapper
    def initialize(static_filter: StaticFilter.new)
      @static_filter = static_filter
    end

    # Runs the test suite to collect coverage, unless a fresh report already
    # exists.
    #
    # @param source_files [Array<String>] lib files whose coverage must be present
    # @param config       [Configuration]
    # @param integration  [Integration::Base]
    # @param test_files   [Array<String>, nil] test files to run; defaults to
    #                     all files reported by the integration when nil
    def ensure!(source_files:, config:, integration:, test_files: nil)
      return if source_files.empty?
      return if coverage_fresh?(source_files, config, integration, test_files)

      bootstrap_coverage(integration, config, test_files)
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

    # Returns true when a coverage report already exists and is newer than
    # every watched source and test file. Stale or absent reports return false.
    def coverage_fresh?(source_files, config, integration, test_files)
      report_path = coverage_report_path(config)
      return false unless File.exist?(report_path)

      report_mtime = File.mtime(report_path)
      watched = Array(source_files) + Array(test_files || integration.test_files)
      watched.all? do |path|
        File.mtime(path) <= report_mtime
      rescue Errno::ENOENT
        false
      end
    end

    def coverage_report_path(config)
      File.join(coverage_dir(config), ".resultset.json")
    end

    def bootstrap_coverage(integration, config, test_files = nil)
      with_coverage_dir(config) do
        result = integration.run_suite(test_files || integration.test_files)
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
