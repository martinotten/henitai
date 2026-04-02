# frozen_string_literal: true

require "etc"

module Henitai
  # Runs pending mutants through the selected integration.
  class ExecutionEngine
    def run(mutants, integration, config, progress_reporter: nil)
      with_reports_dir(config) do
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

    private

    def parallel_execution?(config, mutants)
      worker_count(config) > 1 && mutants.size > 1
    end

    def worker_count(config)
      configured_jobs = config.respond_to?(:jobs) ? config.jobs : nil
      configured_jobs || Etc.nprocessors
    end

    def run_linear(mutants, integration, config, progress_reporter, mutex)
      mutants.each do |mutant|
        process_mutant(mutant, integration, config, progress_reporter, mutex)
      end
    end

    def run_parallel(mutants, integration, config, progress_reporter, mutex)
      queue = Queue.new
      mutants.each { |mutant| queue << mutant }

      Array.new(worker_count(config)) do
        Thread.new do
          loop do
            mutant = queue.pop(true)
            process_mutant(mutant, integration, config, progress_reporter, mutex)
          rescue ThreadError
            break
          end
        end
      end.each(&:join)
    end

    def process_mutant(mutant, integration, config, progress_reporter, mutex)
      test_files = prioritized_tests_for(mutant, integration, config)
      scenario_result = run_with_flaky_retry(mutant, integration, config, test_files, mutex)
      mutant.status = scenario_status(scenario_result)

      if mutex
        mutex.synchronize { progress_reporter&.progress(mutant, scenario_result:) }
      else
        progress_reporter&.progress(mutant, scenario_result:)
      end
    end

    def prioritized_tests_for(mutant, integration, config)
      test_prioritizer.sort(
        integration.select_tests(mutant.subject),
        mutant,
        test_history(config)
      )
    end

    def test_prioritizer
      @test_prioritizer ||= TestPrioritizer.new
    end

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

    def max_flaky_retries(config)
      return 3 unless config.respond_to?(:max_flaky_retries)

      config.max_flaky_retries || 3
    end
  end
end
