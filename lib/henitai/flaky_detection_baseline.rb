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
      first, first_status = run_once(integration, test_files)
      second, second_status = run_once(integration, test_files)
      registry = FlakyTestRegistry.from_outcomes(first, second)
      ensure_usable_suite(registry, [first_status, second_status])
      registry.write(File.join(@reports_dir, FlakyTestRegistry::FILE_NAME))
      warn_flaky(registry)
      registry
    end

    private

    def run_once(integration, test_files)
      outcome_path = TestFileOutcomes.report_path(@reports_dir)
      FileUtils.rm_f(outcome_path)
      status = integration.run_suite(test_files)
      raise CoverageError, "could not record suite outcomes" unless File.exist?(outcome_path)

      [TestFileOutcomes.load(outcome_path).outcomes, status]
    end

    # A failing run is only acceptable as evidence of flakiness: the suite
    # must pass at least once and the failure must be explained by a flaky file.
    def ensure_usable_suite(registry, statuses)
      return if statuses.all?(:survived)
      return if statuses.any?(:survived) && !registry.empty?

      raise CoverageError, "Configured test suite failed while generating coverage"
    end

    def warn_flaky(registry)
      return if registry.empty?

      warn("Flaky tests detected (#{registry.all.size}): #{registry.all.join(', ')}")
    end
  end
end
