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

      # Skip the bootstrap only when the coverage artifacts are both newer than
      # all watched files and actually cover the configured sources. A fresh
      # but irrelevant report (e.g. from a different working directory) must
      # still trigger a re-bootstrap rather than silently proceeding with no
      # usable coverage.
      unless coverage_ready?(source_files, config, integration, test_files)
        bootstrap_coverage(integration, config, test_files)
      end

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

    def coverage_ready?(source_files, config, integration, test_files)
      coverage_fresh?(source_files, config, integration, test_files) &&
        coverage_available?(source_files, config) &&
        per_test_coverage_ready?(source_files, config, integration, test_files)
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

    def per_test_coverage_report_path(config)
      File.join(reports_dir(config), "henitai_per_test.json")
    end

    def bootstrap_coverage(integration, config, test_files = nil)
      with_reports_dir(config) do
        with_coverage_dir(config) do
          result = integration.run_suite(test_files || integration.test_files)
          return if result == :survived

          raise CoverageError, build_bootstrap_error(result)
        end
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

    def with_reports_dir(config)
      original_reports_dir = ENV.fetch("HENITAI_REPORTS_DIR", nil)
      ENV["HENITAI_REPORTS_DIR"] = reports_dir(config)
      yield
    ensure
      if original_reports_dir.nil?
        ENV.delete("HENITAI_REPORTS_DIR")
      else
        ENV["HENITAI_REPORTS_DIR"] = original_reports_dir
      end
    end

    def coverage_dir(config)
      reports_dir = config.respond_to?(:reports_dir) ? config.reports_dir : nil
      return "coverage" if reports_dir.nil? || reports_dir.empty?

      File.join(reports_dir, "coverage")
    end

    def per_test_coverage_fresh?(source_files, config, integration, test_files)
      report_path = per_test_coverage_report_path(config)
      return false unless File.exist?(report_path)

      report_mtime = File.mtime(report_path)
      watched = Array(source_files) + Array(test_files || integration.test_files)
      watched.all? do |path|
        File.mtime(path) <= report_mtime
      rescue Errno::ENOENT
        false
      end
    end

    def per_test_coverage_available?(config)
      File.exist?(per_test_coverage_report_path(config))
    end

    def per_test_coverage_ready?(source_files, config, integration, test_files)
      return true unless per_test_coverage_supported?(integration)

      per_test_coverage_fresh?(source_files, config, integration, test_files) &&
        per_test_coverage_available?(config)
    end

    def per_test_coverage_supported?(integration)
      return false unless integration.respond_to?(:per_test_coverage_supported?)

      integration.per_test_coverage_supported?
    end

    def reports_dir(config)
      return "coverage" unless config.respond_to?(:reports_dir)
      return "coverage" if config.reports_dir.nil? || config.reports_dir.empty?

      config.reports_dir
    end
  end
end
