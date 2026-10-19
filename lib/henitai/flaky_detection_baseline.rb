# frozen_string_literal: true

require "fileutils"

module Henitai
  # Runs the suite twice and persists the test files whose outcome differed.
  #
  # Only used when `mutation.flaky_detection` is enabled. Each run records
  # per-file outcomes via the integration's coverage hooks; the files that
  # disagree between the two runs are written to `henitai_flaky_tests.json`.
  class FlakyDetectionBaseline
    def initialize(reports_dir:)
      @reports_dir = reports_dir
    end

    def run(integration:, test_files:)
      FileUtils.mkdir_p(@reports_dir)
      first, first_result = run_once(integration, test_files)
      second, second_result = run_once(integration, test_files)
      registry = FlakyTestRegistry.from_outcomes(first.outcomes, second.outcomes)
      ensure_usable_suite(registry, [[first, first_result], [second, second_result]])
      registry.write(File.join(@reports_dir, FlakyTestRegistry::FILE_NAME))
      warn_flaky(registry)
      registry
    end

    private

    def run_once(integration, test_files)
      outcome_path = TestFileOutcomes.report_path(@reports_dir)
      FileUtils.rm_f(outcome_path)
      result = integration.run_suite(test_files)
      raise CoverageError, "could not record suite outcomes" unless File.exist?(outcome_path)

      [TestFileOutcomes.load(outcome_path), result]
    end

    # A failing run is only acceptable as evidence of flakiness: the suite
    # must pass at least once and every file that failed in a failing run must
    # be a flaky file. A run that failed without a file to blame (a load error,
    # a suite-level hook) is never explained.
    def ensure_usable_suite(registry, runs)
      failing = runs.reject { |_outcomes, result| result.survived? }
      return if failing.empty?
      return if failing.size < runs.size && failing.all? { |outcomes, _result| explained?(registry, outcomes) }

      raise CoverageError, BootstrapErrorMessage.build(failing.first.last)
    end

    def explained?(registry, outcomes)
      failed = outcomes.failed_files
      !outcomes.unattributed_failures? && !failed.empty? && failed.all? { |file| registry.flaky?(file) }
    end

    def warn_flaky(registry)
      return if registry.empty?

      warn("Flaky tests detected (#{registry.all.size}): #{registry.all.join(', ')}")
    end
  end
end
