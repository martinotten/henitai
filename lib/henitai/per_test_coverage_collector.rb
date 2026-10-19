# frozen_string_literal: true

require "coverage"
require "fileutils"
require "json"
require_relative "per_test_coverage_delta"
require_relative "suite_boot_clock"

module Henitai
  # Accumulates per-test line coverage deltas across test examples.
  # {PerTestCoverageDelta} decides which lines a single test executed.
  #
  # Framework-agnostic core used by both the RSpec and Minitest adapters.
  # Callers invoke record_test after each test completes and write_report
  # once the full suite has finished.
  class PerTestCoverageCollector
    REPORT_DIR_ENV = "HENITAI_REPORTS_DIR"
    REPORT_FILE_NAME = "henitai_per_test.json"
    BOOT_FILE_NAME = "henitai_suite_boot.json"

    # @param boot_clock [SuiteBootClock] measures suite boot time
    def initialize(boot_clock: SuiteBootClock.from_env(ENV))
      @boot_clock = boot_clock
      @coverage_by_test = Hash.new do |hash, test_file|
        hash[test_file] = Hash.new { |nested, source_file| nested[source_file] = [] }
      end
      @duration_by_test = Hash.new(0.0)
      @previous_snapshot = {}
      @delta = PerTestCoverageDelta.new
      @warned_missing_coverage = false
    end

    # Called when the first test of the suite starts; ends the boot phase.
    def test_started
      @boot_clock.mark_first_test_started
    end

    def record_test(test_file, duration: nil)
      snapshot = current_snapshot
      return warn_missing_coverage unless snapshot

      new_lines(snapshot).each do |source_file, lines|
        @coverage_by_test[test_file][source_file].concat(lines)
        @coverage_by_test[test_file][source_file].uniq!
        @coverage_by_test[test_file][source_file].sort!
      end
      @duration_by_test[test_file] += duration.to_f
      @previous_snapshot = snapshot
    end

    def write_report
      return if @coverage_by_test.empty?

      FileUtils.mkdir_p(reports_dir)
      File.write(report_path, JSON.pretty_generate(serializable_report))
      File.write(boot_path, JSON.pretty_generate("boot_seconds" => @boot_clock.boot_seconds))
    end

    private

    def report_path
      File.join(reports_dir, REPORT_FILE_NAME)
    end

    def boot_path
      File.join(reports_dir, BOOT_FILE_NAME)
    end

    def reports_dir
      ENV.fetch(REPORT_DIR_ENV, "coverage")
    end

    def current_snapshot
      Coverage.peek_result
    rescue RuntimeError
      # Raised when coverage measurement is not running; caller warns and skips.
      # Other errors are genuine bugs and must surface.
      nil
    end

    def warn_missing_coverage
      return if @warned_missing_coverage
      return if coverage_suppressed?

      warn "Per-test coverage unavailable; skipping coverage formatter output"
      @warned_missing_coverage = true
    end

    # Mutant children deliberately suppress coverage startup
    # (CoverageRuntimeSuppressors), so missing coverage is expected there and
    # warning on every child run is pure noise.
    def coverage_suppressed?
      defined?(Henitai::Integration::CoverageRuntimeSuppressors) &&
        Henitai::Integration::CoverageRuntimeSuppressors.active?
    end

    def new_lines(snapshot)
      snapshot.each_with_object({}) do |(source_file, file_coverage), result|
        next unless source_file?(source_file)

        lines = @delta.executed_lines(file_coverage, @previous_snapshot.fetch(source_file, []))
        result[source_file] = lines unless lines.empty?
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
      @coverage_by_test.to_h do |test_file, source_map|
        coverage = source_map.to_h do |source_file, lines|
          [File.expand_path(source_file), lines.uniq.sort]
        end
        [test_file, { "coverage" => coverage, "duration" => @duration_by_test[test_file] }]
      end
    end
  end
end
