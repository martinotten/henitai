# frozen_string_literal: true

module Henitai
  # Runs pending mutants through the selected integration.
  class ExecutionEngine
    # The orchestration boundary is intentionally small and linear.
    # rubocop:disable Metrics/MethodLength
    def run(mutants, integration, config, progress_reporter: nil)
      original_reports_dir = ENV.fetch("HENITAI_REPORTS_DIR", nil)
      ENV["HENITAI_REPORTS_DIR"] = config.reports_dir

      mutants.each do |mutant|
        next unless mutant.pending?

        test_files = integration.select_tests(mutant.subject)
        mutant.status = integration.run_mutant(
          mutant:,
          test_files:,
          timeout: config.timeout
        )
        progress_reporter&.progress(mutant)
      end
      mutants
    ensure
      if original_reports_dir.nil?
        ENV.delete("HENITAI_REPORTS_DIR")
      else
        ENV["HENITAI_REPORTS_DIR"] = original_reports_dir
      end
    end
    # rubocop:enable Metrics/MethodLength
  end
end
