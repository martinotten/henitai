# frozen_string_literal: true

module Henitai
  module Integration
    # Runs RSpec child and suite processes on behalf of the integration.
    class RspecProcessRunner
      def run_mutant(integration, mutant:, test_files:, timeout:)
        log_paths = integration.send(:scenario_log_paths, mutant_log_name(mutant))
        pid = fork_mutant_process(integration, mutant, test_files, log_paths)
        wait_result = integration.send(:wait_with_timeout, pid, timeout)
        integration.send(:build_result, wait_result, log_paths)
      ensure
        finalize_mutant_run(integration, pid, wait_result)
      end

      def run_suite(integration, test_files, timeout:)
        log_paths = integration.send(:scenario_log_paths, "baseline")
        wait_result = nil
        FileUtils.mkdir_p(File.dirname(log_paths[:stdout_path]))
        pid = integration.send(:spawn_suite_process, test_files, log_paths)
        wait_result = integration.send(:wait_with_timeout, pid, timeout)
        integration.send(:build_result, wait_result, log_paths)
      ensure
        if pid
          integration.send(:cleanup_process_group, pid) unless wait_result == :timeout
          integration.send(:reap_child, pid) if wait_result.nil?
        end
      end

      private

      def fork_mutant_process(integration, mutant, test_files, log_paths)
        Process.fork do
          Process.setpgid(0, 0)
          ENV["HENITAI_MUTANT_ID"] = mutant.id
          Process.exit(
            integration.send(
              :run_in_child,
              mutant: mutant,
              test_files: test_files,
              log_paths: log_paths
            )
          )
        end
      end

      def finalize_mutant_run(integration, pid, wait_result)
        return unless pid

        integration.send(:cleanup_process_group, pid) unless wait_result == :timeout
        integration.send(:reap_child, pid) if wait_result.nil?
      end

      def mutant_log_name(mutant)
        "mutant-#{mutant.id}"
      end
    end
  end
end
