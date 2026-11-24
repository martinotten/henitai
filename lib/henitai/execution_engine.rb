# frozen_string_literal: true

require_relative "process_worker_runner"
require_relative "execution_engine/env_scope"
require_relative "execution_engine/fork_server_scope"

module Henitai
  # Runs pending mutants through the selected integration.
  #
  # Every run, whatever `jobs` says, goes through one {ProcessWorkerRunner}
  # (ADR-20): `jobs` is only its slot count. The engine supplies what the
  # scheduler cannot know: which tests a mutant runs, its timeout, the flaky
  # set, control runs and the fork server.
  class ExecutionEngine
    include EnvScope
    include ForkServerScope

    # @param runtime [ProcessWorkerRunner::Runtime, nil] process primitives of
    #   the worker runner; nil uses the real ones. Replaced by the fork
    #   server's runtime while a server is active.
    # @param wakeup [ProcessWakeup, nil] the runner's wakeup; nil installs one
    def initialize(runtime: nil, wakeup: nil)
      @runtime = runtime
      @wakeup = wakeup
    end

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

    # Verdicts pass a ControlGate before any observer sees them (ADR-19); the
    # worker runner builds the gate and runs its controls as scheduler jobs.
    def execute(mutants, integration, config, progress_reporter)
      pending_mutants = Array(mutants).select(&:pending?)
      @flaky_tests = flaky_tests_for(config)
      @kill_history = KillHistory.new
      control_run = ControlRun.new if control_runs?(config)
      runner = with_fork_server(pending_mutants, integration, config) do
        run_workers(pending_mutants, integration, config, progress_reporter, control_run)
      end
      warn_control_failures(runner.control_stats) if control_run
      warn_flaky_mutants(runner.flaky_retry_count)
      mutants
    end

    def control_runs?(config) = config.respond_to?(:control_runs) && config.control_runs

    def warn_control_failures(stats)
      return if stats[:failed].zero?

      warn format("henitai: control runs failed for %<failed>d of %<verified>d subjects; " \
                  "%<reclassified>d detected verdicts reclassified as CompileError", **stats)
    end

    # `jobs` is a slot count; unset or zero means one slot. The default stays
    # conservative: AvailableCpuCount exists as a future policy hook.
    def worker_count(config)
      [config.jobs.to_i, 1].max
    end

    def run_workers(mutants, integration, config, progress_reporter, control_run)
      runner = ProcessWorkerRunner.new(worker_count: worker_count(config), flaky_tests: @flaky_tests,
                                       **runner_primitives)
      observers = CompositeProgressReporter.new([@kill_history, progress_reporter])
      runner.run(mutants, @fork_server_runner || integration, config, observers,
                 **run_options(integration, config, control_run))
      runner
    end

    def runner_primitives
      { runtime: @runtime, wakeup: @wakeup }.compact.merge(fork_server_runtime_options)
    end

    def run_options(integration, config, control_run)
      {
        test_file_resolver: ->(mutant) { prioritized_tests_for(mutant, integration, config) },
        timeout_resolver: ->(_mutant, test_files) { resolved_timeout(test_files, config) },
        control_run:
      }
    end

    def prioritized_tests_for(mutant, integration, config)
      tests = per_test_coverage_selector.select(
        mutant,
        reports_dir: config.reports_dir,
        test_files: -> { reject_excluded_tests(integration.test_files, config) },
        fallback: -> { reject_excluded_tests(integration.select_tests(mutant.subject), config) }
      )
      test_prioritizer(config).sort(tests, mutant, @kill_history)
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

    # Boot stays in the timeout even with a fork server: served mutants still
    # run the suite's before(:suite) hooks, which the boot measurement includes.
    def timeout_calibrator(config)
      @timeout_calibrator ||= TimeoutCalibrator.new(
        timing_source: timing_source(config),
        multiplier: config.timeout_multiplier,
        boot_seconds: -> { boot_seconds(config) }
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

    def flaky_tests_for(config)
      FlakyTestRegistry.for_config(config)
    end

    def warn_flaky_mutants(count)
      return if count.zero?

      warn format(
        "Flaky-test mitigation: %<count>d killed mutant(s) were re-checked because their killing tests " \
        "are flaky (%<files>s)",
        count:,
        files: @flaky_tests.all.join(", ")
      )
    end
  end
end
