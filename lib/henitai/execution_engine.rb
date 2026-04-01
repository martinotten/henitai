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

    def process_mutant(mutant, integration, config, progress_reporter, mutex = nil)
      test_files = prioritized_tests_for(mutant, integration, config)
      mutant.status = run_with_flaky_retry(mutant, integration, config, test_files, mutex)

      if mutex
        mutex.synchronize { progress_reporter&.progress(mutant) }
      else
        progress_reporter&.progress(mutant)
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
    # rubocop:disable Metrics/MethodLength
    def run_with_flaky_retry(mutant, integration, config, test_files, mutex)
      status = integration.run_mutant(
        mutant:,
        test_files:,
        timeout: config.timeout
      )
      return status unless status == :survived

      retries = 0
      3.times do
        retries += 1
        status = integration.run_mutant(
          mutant:,
          test_files:,
          timeout: config.timeout
        )
        break unless status == :survived
      end

      mutex.synchronize { @flaky_retry_count += 1 } if retries.positive?
      status
    end
    # rubocop:enable Metrics/MethodLength

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
  end
end
