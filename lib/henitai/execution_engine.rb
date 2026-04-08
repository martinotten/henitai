# frozen_string_literal: true

module Henitai
  # Runs pending mutants through the selected integration.
  class ExecutionEngine
    ParallelExecutionContext = Struct.new(:queue, :integration, :config, :progress_reporter,
                                          :mutex, :state, :old_handlers, :stdin_watcher)

    def run(mutants, integration, config, progress_reporter: nil)
      with_reports_dir(config) do
        with_coverage_dir(config) do
          @flaky_retry_count = 0
          pending_mutants = Array(mutants).select(&:pending?)
          mutex = Mutex.new
          if parallel_execution?(config, pending_mutants)
            run_parallel(pending_mutants, integration, config, progress_reporter, mutex)
          else
            run_linear(pending_mutants, integration, config, progress_reporter, mutex)
          end

          warn_flaky_mutants(pending_mutants.size)
          mutants
        end
      end
    end

    private

    def parallel_execution?(config, mutants)
      worker_count(config) > 1 && mutants.size > 1
    end

    def worker_count(config)
      configured_jobs = config.respond_to?(:jobs) ? config.jobs : nil
      configured_jobs || 1
    end

    def run_linear(mutants, integration, config, progress_reporter, mutex)
      mutants.each do |mutant|
        process_mutant(mutant, integration, config, progress_reporter, mutex)
      end
    end

    def run_parallel(mutants, integration, config, progress_reporter, mutex)
      context = build_parallel_context(
        mutants,
        integration,
        config,
        progress_reporter,
        mutex
      )
      install_parallel_signal_traps(context)
      start_parallel_stdin_watcher(context) if pipe_stdin?
      parallel_workers(context).each(&:join)
    ensure
      stop_parallel_stdin_watcher(context)
      restore_parallel_signal_traps(context)
      raise Interrupt if context&.state&.fetch(:stopping, false)
    end

    def pipe_stdin?
      $stdin.stat.pipe?
    rescue Errno::EBADF
      false
    end

    def build_parallel_queue(mutants)
      Queue.new.tap { |queue| mutants.each { |mutant| queue << mutant } }
    end

    def build_parallel_context(mutants, integration, config, progress_reporter, mutex)
      ParallelExecutionContext.new(
        build_parallel_queue(mutants), integration, config, progress_reporter,
        mutex, { stopping: false }
      )
    end

    def install_parallel_signal_traps(context)
      context.old_handlers = {
        int: trap(:INT) { stop_parallel_execution(context) },
        term: trap(:TERM) { stop_parallel_execution(context) },
        hup: trap(:HUP) { stop_parallel_execution(context) }
      }
    end

    def stop_parallel_execution(context)
      context.state[:stopping] = true
      context.queue.clear
    end

    def start_parallel_stdin_watcher(context)
      context.stdin_watcher = Thread.new do
        $stdin.read
        stop_parallel_execution(context)
      rescue IOError, Errno::EBADF
        nil
      end
    end

    def parallel_workers(context)
      Array.new(worker_count(context.config)) { Thread.new { process_parallel_worker(context) } }
    end

    def process_parallel_worker(context)
      loop do
        break if context.state[:stopping]

        process_mutant(
          context.queue.pop(true),
          context.integration,
          context.config,
          context.progress_reporter,
          context.mutex
        )
      rescue ThreadError
        break
      end
    end

    def stop_parallel_stdin_watcher(context)
      context&.stdin_watcher&.kill
    end

    def restore_parallel_signal_traps(context)
      handlers = context&.old_handlers
      return unless handlers

      trap(:INT, handlers[:int] || "DEFAULT")
      trap(:TERM, handlers[:term] || "DEFAULT")
      trap(:HUP, handlers[:hup] || "DEFAULT")
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
      tests = integration.select_tests(mutant.subject)
      tests = per_test_coverage_selector.filter(
        tests,
        mutant,
        reports_dir: config.reports_dir
      )
      test_prioritizer.sort(tests, mutant, test_history(config))
    end

    def test_prioritizer = @test_prioritizer ||= TestPrioritizer.new

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
      scenario_result = integration.run_mutant(
        mutant:,
        test_files:,
        timeout: config.timeout
      )
      return scenario_result unless scenario_status(scenario_result) == :survived

      retries = 0
      max_flaky_retries(config).times do
        retries += 1
        scenario_result = integration.run_mutant(
          mutant:,
          test_files:,
          timeout: config.timeout
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

    def with_reports_dir(config)
      original_reports_dir = ENV.fetch("HENITAI_REPORTS_DIR", nil)
      ENV["HENITAI_REPORTS_DIR"] = config.reports_dir
      yield
    ensure
      if original_reports_dir.nil?
        ENV.delete("HENITAI_REPORTS_DIR")
      else
        ENV["HENITAI_REPORTS_DIR"] = original_reports_dir
      end
    end

    def with_coverage_dir(config)
      original_coverage_dir = ENV.fetch("HENITAI_COVERAGE_DIR", nil)
      ENV["HENITAI_COVERAGE_DIR"] = mutation_coverage_dir(config)
      yield
    ensure
      if original_coverage_dir.nil?
        ENV.delete("HENITAI_COVERAGE_DIR")
      else
        ENV["HENITAI_COVERAGE_DIR"] = original_coverage_dir
      end
    end

    def mutation_coverage_dir(config)
      base_dir = config.respond_to?(:reports_dir) ? config.reports_dir : nil
      base_dir = "reports" if base_dir.nil? || base_dir.empty?

      File.join(base_dir, "mutation-coverage")
    end

    def max_flaky_retries(config)
      return 3 unless config.respond_to?(:max_flaky_retries)

      config.max_flaky_retries || 3
    end
  end
end
