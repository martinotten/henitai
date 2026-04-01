# frozen_string_literal: true

require "etc"

module Henitai
  # Runs pending mutants through the selected integration.
  class ExecutionEngine
    def run(mutants, integration, config, progress_reporter: nil)
      with_reports_dir(config) do
        pending_mutants = Array(mutants).select(&:pending?)
        if parallel_execution?(config, pending_mutants)
          run_parallel(pending_mutants, integration, config, progress_reporter)
        else
          run_linear(pending_mutants, integration, config, progress_reporter)
        end

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

    def run_linear(mutants, integration, config, progress_reporter)
      mutants.each do |mutant|
        process_mutant(mutant, integration, config, progress_reporter)
      end
    end

    def run_parallel(mutants, integration, config, progress_reporter)
      queue = Queue.new
      mutants.each { |mutant| queue << mutant }
      mutex = Mutex.new

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
      test_files = integration.select_tests(mutant.subject)
      mutant.status = integration.run_mutant(
        mutant:,
        test_files:,
        timeout: config.timeout
      )

      if mutex
        mutex.synchronize { progress_reporter&.progress(mutant) }
      else
        progress_reporter&.progress(mutant)
      end
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
