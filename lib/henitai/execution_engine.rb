# frozen_string_literal: true

module Henitai
  # Runs pending mutants through the selected integration.
  class ExecutionEngine
    def run(mutants, integration, config)
      mutants.each do |mutant|
        next unless mutant.pending?

        test_files = integration.select_tests(mutant.subject)
        mutant.status = integration.run_mutant(
          mutant:,
          test_files:,
          timeout: config.timeout
        )
      end

      mutants
    end
  end
end
