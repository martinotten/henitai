# frozen_string_literal: true

require "fileutils"
require "json"

require_relative "verdict_fingerprint"

module Henitai
  # Ensures coverage data exists before the mutation pipeline starts.
  class CoverageBootstrapper
    # Sidecar recording which dependency files existed when the coverage
    # artifacts were produced. Deletions drop a path from the current set but
    # leave every surviving file's mtime untouched, so freshness must compare
    # the recorded path set, not just watch existing files.
    DEPENDENCY_MANIFEST_FILE = "henitai_dependency_manifest.json"

    def initialize(static_filter: StaticFilter.new)
      @static_filter = static_filter
    end

    # Writes the current dependency path set next to the coverage artifacts.
    # Called after every bootstrap; exposed so tests can seed a manifest.
    def record_dependency_manifest(config)
      FileUtils.mkdir_p(reports_dir(config))
      File.write(dependency_manifest_path(config), JSON.generate(current_dependency_paths))
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

      resolved_test_files = resolve_test_files(integration, test_files)

      # Skip the bootstrap only when the coverage artifacts are both newer than
      # all watched files and actually cover the configured sources. A fresh
      # but irrelevant report (e.g. from a different working directory) must
      # still trigger a re-bootstrap rather than silently proceeding with no
      # usable coverage.
      unless coverage_ready?(source_files, config, integration, resolved_test_files)
        bootstrap_coverage(integration, config, resolved_test_files)
      end

      return if coverage_available?(source_files, config)

      raise CoverageError,
            "Coverage data is unavailable for the configured source files"
    end

    private

    attr_reader :static_filter

    def coverage_available?(source_files, config)
      coverage_lines = static_filter.coverage_lines_for(config)
      covered_sources = covered_source_files(source_files, coverage_lines)

      covered_sources.any?
    end

    def coverage_ready?(source_files, config, integration, test_files)
      coverage_fresh?(source_files, config, test_files) &&
        coverage_available?(source_files, config) &&
        per_test_coverage_ready?(source_files, config, integration, test_files)
    end

    def covered_source_files(source_files, coverage_lines)
      source_file_paths(source_files).select do |path|
        Array(coverage_lines[path]).any?
      end
    end

    def source_file_paths(source_files)
      Array(source_files).map { |path| File.expand_path(path) }
    end

    # Returns true when a coverage report already exists, is newer than every
    # watched source and test file, and the dependency path set is unchanged
    # since the report was produced. Stale or absent reports return false.
    def coverage_fresh?(source_files, config, test_files)
      watched_files_fresh?(
        coverage_report_path(config),
        source_files,
        test_files
      ) && dependency_manifest_current?(config)
    end

    # False when the manifest is missing, unreadable, or lists a different
    # path set than the files currently on disk — conservative: a deleted
    # dependency invalidates the coverage artifacts just like an edit.
    def dependency_manifest_current?(config)
      recorded = JSON.parse(File.read(dependency_manifest_path(config)))
      recorded == current_dependency_paths
    rescue StandardError
      false
    end

    def dependency_manifest_path(config)
      File.join(reports_dir(config), DEPENDENCY_MANIFEST_FILE)
    end

    # Paths stored relative to the working directory so the manifest survives
    # a repository move.
    def current_dependency_paths
      root = Dir.pwd
      VerdictFingerprint.dependency_files(root).map do |path|
        path.delete_prefix("#{root}#{File::SEPARATOR}")
      end
    end

    def coverage_report_path(config)
      File.join(coverage_dir(config), ".resultset.json")
    end

    def per_test_coverage_report_path(config)
      File.join(reports_dir(config), "henitai_per_test.json")
    end

    def bootstrap_coverage(integration, config, test_files = nil)
      test_files ||= integration.test_files

      with_reports_dir(config) do
        with_coverage_dir(config) do
          result = integration.run_suite(test_files)
          if result == :survived
            record_dependency_manifest(config)
            return
          end

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

    def per_test_coverage_fresh?(source_files, config, test_files)
      watched_files_fresh?(
        per_test_coverage_report_path(config),
        source_files,
        test_files
      )
    end

    def per_test_coverage_available?(config)
      File.exist?(per_test_coverage_report_path(config))
    end

    def per_test_coverage_ready?(source_files, config, integration, test_files)
      return true unless per_test_coverage_supported?(integration)

      per_test_coverage_fresh?(source_files, config, test_files) &&
        per_test_coverage_available?(config)
    end

    def per_test_coverage_supported?(integration)
      return false unless integration.respond_to?(:per_test_coverage_supported?)

      integration.per_test_coverage_supported?
    end

    def watched_files_fresh?(report_path, source_files, test_files)
      # This check assumes a single writer owns the coverage artifacts for the
      # workspace. It is intentionally not an atomic snapshot-and-validate step.
      return false unless File.exist?(report_path)

      report_mtime = File.mtime(report_path)
      watched_files(source_files, test_files).all? do |path|
        File.mtime(path) <= report_mtime
      rescue Errno::ENOENT
        false
      end
    end

    # Dependency files (helpers, support, fixtures, lockfile, tool config)
    # are watched alongside sources and tests: they shape which tests cover
    # what, so a stale per-test map after a dependency edit would let the
    # test selector omit a newly covering test (ADR-11).
    def watched_files(source_files, test_files)
      Array(source_files) + Array(test_files) + VerdictFingerprint.dependency_files
    end

    def resolve_test_files(integration, test_files)
      return test_files unless test_files.nil?

      integration.test_files
    end

    def reports_dir(config)
      return "coverage" unless config.respond_to?(:reports_dir)
      return "coverage" if config.reports_dir.nil? || config.reports_dir.empty?

      config.reports_dir
    end
  end
end
