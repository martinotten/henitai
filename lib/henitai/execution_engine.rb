# frozen_string_literal: true

require_relative "process_worker_runner"
require_relative "execution_engine/env_scope"

module Henitai
  # Runs pending mutants through the selected integration.
  class ExecutionEngine
    include EnvScope

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
      @flaky_retry_count = 0
      pending_mutants = Array(mutants).select(&:pending?)
      mutex = Mutex.new
      if parallel_execution?(config, pending_mutants)
        run_parallel(pending_mutants, integration, config, progress_reporter)
      else
        run_linear(pending_mutants, integration, config, progress_reporter, mutex)
      end

      warn_flaky_mutants(pending_mutants.size)
      mutants
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
      runner = ProcessWorkerRunner.new(worker_count: worker_count(config))
      results = runner.run(
        mutants,
        integration,
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
      mutant.covered_by = test_files if mutant.respond_to?(:covered_by=)
      mutant.tests_completed = test_files.size if mutant.respond_to?(:tests_completed=)
      scenario_result = run_with_flaky_retry(mutant, integration, config, test_files, mutex)
      mutant.status = scenario_status(scenario_result)

      if mutex
        mutex.synchronize { progress_reporter&.progress(mutant, scenario_result:) }
      else
        progress_reporter&.progress(mutant, scenario_result:)
      end
    end

    def prioritized_tests_for(mutant, integration, config)
      tests = reject_excluded_tests(integration.select_tests(mutant.subject), config)
      tests = per_test_coverage_selector.filter(
        tests,
        mutant,
        reports_dir: config.reports_dir
      )
      test_prioritizer(config).sort(tests, mutant, test_history(config))
    end

    # Drops test files matching any config.test_excludes glob. Used to keep a
    # mutant child from re-running tests that themselves spawn henitai/forked
    # subprocesses (e.g. the CLI and process-scheduler specs when dogfooding
    # henitai on itself), which otherwise multiplies processes and log noise.
    def reject_excluded_tests(tests, config)
      patterns = config.respond_to?(:test_excludes) ? Array(config.test_excludes) : []
      return tests if patterns.empty?

      expanded = patterns.map { |pattern| File.expand_path(pattern) }
      tests.reject do |path|
        candidate = File.expand_path(path)
        expanded.any? { |pattern| File.fnmatch?(pattern, candidate, File::FNM_PATHNAME) }
      end
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

      calibrated = timeout_calibrator(config).timeout_for(test_files)
      return [calibrated, max_timeout(config)].min if calibrated

      warn_timeout_fallback_once
      Configuration::DEFAULT_TIMEOUT
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
      @timeout_calibrator ||= TimeoutCalibrator.new(
        timing_source: timing_source(config),
        multiplier: config.timeout_multiplier
      )
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

    # Retry logic is kept in one place to preserve the status transition flow.
    # The retry budget is configurable because repeated survivors can multiply
    # runtime on real CI workloads.
    # rubocop:disable Metrics/MethodLength
    def run_with_flaky_retry(mutant, integration, config, test_files, mutex)
      timeout = resolved_timeout(test_files, config)
      scenario_result = integration.run_mutant(
        mutant:,
        test_files:,
        timeout: timeout
      )
      return scenario_result unless scenario_status(scenario_result) == :survived

      retries = 0
      max_flaky_retries(config).times do
        retries += 1
        scenario_result = integration.run_mutant(
          mutant:,
          test_files:,
          timeout: timeout
        )
        break unless scenario_status(scenario_result) == :survived
      end

      mutex.synchronize { @flaky_retry_count += 1 } if retries.positive?
      scenario_result
    end
    # rubocop:enable Metrics/MethodLength

    def scenario_status(result)
      return result if result.is_a?(Symbol)

      result.status
    end

    def warn_flaky_mutants(total_mutants)
      return if total_mutants.zero?

      flaky_ratio = @flaky_retry_count.to_f / total_mutants
      return unless flaky_ratio > 0.05

      warn format(
        "Flaky-test mitigation: %<flaky>d/%<total>d mutants required retries (%<ratio>.2f%%)",
        flaky: @flaky_retry_count,
        total: total_mutants,
        ratio: flaky_ratio * 100.0
      )
    end

    def max_flaky_retries(config)
      return 3 unless config.respond_to?(:max_flaky_retries)

      config.max_flaky_retries || 3
    end
  end
end
