# frozen_string_literal: true

require_relative "process_worker_runner"
require_relative "execution_engine/env_scope"
require_relative "execution_engine/fork_server_scope"

module Henitai
  # Runs pending mutants through the selected integration.
  class ExecutionEngine
    include EnvScope
    include ForkServerScope

    def run(mutants, integration, config, progress_reporter: nil)
      with_reports_dir(config) do
        with_coverage_dir(config) do
          with_max_log_bytes(config) do
            with_worker_slot do
              execute(mutants, integration, config, progress_reporter)
            end
          end
        end
      end
    end

    private

    def execute(mutants, integration, config, progress_reporter)
      pending_mutants = Array(mutants).select(&:pending?)
      mutex = Mutex.new
      @flaky_tests = flaky_tests_for(config)
      @retrier = FlakyMutantRetrier.new(flaky_tests: @flaky_tests, max_retries: max_flaky_retries(config))
      run_pending(pending_mutants, integration, config, progress_reporter, mutex)
      warn_flaky_mutants
      verify_controls(pending_mutants, integration, config)
      mutants
    end

    def run_pending(pending_mutants, integration, config, progress_reporter, mutex)
      with_fork_server(pending_mutants, integration, config) do
        if parallel_execution?(config, pending_mutants)
          run_parallel(pending_mutants, integration, config, progress_reporter)
        else
          run_linear(pending_mutants, integration, config, progress_reporter, mutex)
          @flaky_retry_count = @retrier.retried_count
        end
      end
    end

    def verify_controls(mutants, integration, config)
      return unless config.respond_to?(:control_runs) && config.control_runs

      timeout_for = ->(test_files) { resolved_timeout(test_files, config) }
      stats = ControlRun.new(integration:, timeout_for:).verify(mutants)
      return if stats[:failed].zero?

      warn format("henitai: control runs failed for %<failed>d of %<verified>d subjects; " \
                  "%<reclassified>d detected verdicts reclassified as CompileError", **stats)
    end

    def parallel_execution?(config, mutants)
      worker_count(config) > 1 && mutants.size > 1
    end

    def worker_count(config)
      configured_jobs = config.respond_to?(:jobs) ? config.jobs : nil
      return configured_jobs if configured_jobs

      # The fallback stays conservative for now; the execution policy still
      # defaults to a single worker even though AvailableCpuCount exists as a
      # future policy hook.
      1
    end

    def run_linear(mutants, integration, config, progress_reporter, mutex)
      mutants.each do |mutant|
        process_mutant(mutant, integration, config, progress_reporter, mutex)
      end
    end

    def run_parallel(mutants, integration, config, progress_reporter)
      runner = ProcessWorkerRunner.new(
        worker_count: worker_count(config),
        flaky_tests: @flaky_tests,
        **parallel_runtime_options
      )
      results = runner.run(
        mutants,
        @fork_server_runner || integration,
        config,
        progress_reporter,
        test_file_resolver: ->(mutant) { prioritized_tests_for(mutant, integration, config) },
        timeout_resolver: ->(_mutant, test_files) { resolved_timeout(test_files, config) }
      )
      @flaky_retry_count = runner.flaky_retry_count
      results
    end

    def process_mutant(mutant, integration, config, progress_reporter, mutex)
      test_files = prioritized_tests_for(mutant, integration, config)
      record_test_files(mutant, test_files)
      return record_no_coverage(mutant, progress_reporter, mutex) if test_files.empty?

      scenario_result = @retrier.run(
        mutant: mutant, integration: @fork_server_runner || integration, test_files: test_files,
        timeout: resolved_timeout(test_files, config)
      )
      mutant.status = scenario_status(scenario_result)
      ScenarioExecutionResult.copy_reason(scenario_result, mutant)

      report_progress(mutant, scenario_result, progress_reporter, mutex)
    end

    def record_test_files(mutant, test_files)
      mutant.covered_by = test_files if mutant.respond_to?(:covered_by=)
      mutant.tests_completed = test_files.size if mutant.respond_to?(:tests_completed=)
    end

    def record_no_coverage(mutant, progress_reporter, mutex)
      mutant.status = :no_coverage
      report_progress(mutant, nil, progress_reporter, mutex)
    end

    def report_progress(mutant, scenario_result, progress_reporter, mutex)
      if mutex
        mutex.synchronize { progress_reporter&.progress(mutant, scenario_result:) }
      else
        progress_reporter&.progress(mutant, scenario_result:)
      end
    end

    def prioritized_tests_for(mutant, integration, config)
      tests = per_test_coverage_selector.select(
        mutant,
        reports_dir: config.reports_dir,
        test_files: -> { reject_excluded_tests(integration.test_files, config) },
        fallback: -> { reject_excluded_tests(integration.select_tests(mutant.subject), config) }
      )
      test_prioritizer(config).sort(tests, mutant, test_history(config))
    end

    def reject_excluded_tests(tests, config)
      ExcludedTestFilter.new(patterns: configured_test_excludes(config)).reject(tests)
    end

    # Specs pass bare config doubles exposing only what the example needs.
    def configured_test_excludes(config)
      config.respond_to?(:test_excludes) ? config.test_excludes : nil
    end

    def test_prioritizer(config)
      @test_prioritizer ||= TestPrioritizer.new(timing_source: timing_source(config))
    end

    def timing_source(config)
      path = File.join(config.reports_dir, PerTestCoverageCollector::REPORT_FILE_NAME)
      -> { CoverageReportReader.new.durations_by_test(path) }
    end

    # Fixed `mutation.timeout` wins untouched; when unset, the timeout is
    # calibrated per mutant from its selected tests' measured durations, with
    # a single warning per run when no timing data is available.
    def resolved_timeout(test_files, config)
      return config.timeout unless calibration_enabled?(config)

      calibrator = timeout_calibrator(config)
      calibrated = calibrator.timeout_for(test_files)
      unless calibrated
        warn_timeout_fallback_once
        return Configuration::DEFAULT_TIMEOUT
      end

      timeout_ceiling(config).cap(calibrated, calibrator.baseline_for(test_files))
    end

    def timeout_ceiling(config)
      @timeout_ceiling ||= TimeoutCeiling.new(
        ceiling: max_timeout(config),
        warner: ->(message) { warn(message) }
      )
    end

    # Ceiling on the auto-calibrated timeout so a runaway mutant is killed in
    # seconds instead of running for minutes when the calibrated value (derived
    # from a slow baseline) is large. A fixed mutation.timeout bypasses this.
    def max_timeout(config)
      return config.max_timeout if config.respond_to?(:max_timeout) && config.max_timeout

      Configuration::DEFAULT_MAX_TIMEOUT
    end

    def calibration_enabled?(config)
      config.respond_to?(:timeout_configured?) && !config.timeout_configured?
    end

    def timeout_calibrator(config)
      include_boot = calibration_includes_boot?
      @timeout_calibrators ||= {}
      @timeout_calibrators[include_boot] ||= TimeoutCalibrator.new(
        timing_source: timing_source(config),
        multiplier: config.timeout_multiplier,
        boot_seconds: -> { boot_seconds(config) },
        include_boot: include_boot
      )
    end

    def boot_seconds(config)
      path = File.join(config.reports_dir, PerTestCoverageCollector::BOOT_FILE_NAME)
      CoverageReportReader.new.boot_seconds(path)
    end

    def warn_timeout_fallback_once
      return if @warned_timeout_fallback

      @warned_timeout_fallback = true
      warn(
        "Timeout calibration unavailable (no per-test timing data); " \
        "falling back to the default timeout of #{Configuration::DEFAULT_TIMEOUT}s"
      )
    end

    def per_test_coverage_selector = @per_test_coverage_selector ||= PerTestCoverageSelector.new

    def test_history(config)
      return {} unless config.respond_to?(:history)

      config.history || {}
    end

    def flaky_tests_for(config)
      FlakyTestRegistry.for_config(config)
    end

    def scenario_status(result)
      return result if result.is_a?(Symbol)

      result.status
    end

    def warn_flaky_mutants
      return if @flaky_retry_count.to_i.zero?

      warn format(
        "Flaky-test mitigation: %<count>d killed mutant(s) were re-checked because their killing tests " \
        "are flaky (%<files>s)",
        count: @flaky_retry_count,
        files: @flaky_tests.all.join(", ")
      )
    end

    def max_flaky_retries(config)
      return 3 unless config.respond_to?(:max_flaky_retries)

      config.max_flaky_retries || 3
    end
  end
end
