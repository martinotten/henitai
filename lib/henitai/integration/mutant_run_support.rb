# frozen_string_literal: true

require "fileutils"

module Henitai
  module Integration
    # Framework-agnostic orchestration for running a single mutant in a child
    # process and turning the captured child output into a ScenarioExecutionResult.
    #
    # The framework-specific test invocation is delegated to #run_tests, which
    # including classes must implement.
    module MutantRunSupport
      # The previous attempt's report is cleared before the fork, so a retried
      # child that dies early can never be classified by stale data.
      def spawn_mutant(mutant:, test_files:)
        log_paths = mutant_log_paths(mutant)
        child_report_store.clear(log_paths[:report_path])
        RspecProcessRunner.new.spawn_mutant(self, mutant:, test_files:, log_paths:)
      end

      def run_mutant(mutant:, test_files:, timeout:)
        RspecProcessRunner.new.run_mutant(self, mutant:, test_files:, timeout:)
      end

      def scenario_log_paths(name)
        reports_dir = ENV.fetch("HENITAI_REPORTS_DIR", "reports")
        log_dir = File.join(reports_dir, "mutation-logs")
        {
          stdout_path: File.join(log_dir, "#{name}.stdout.log"),
          stderr_path: File.join(log_dir, "#{name}.stderr.log"),
          log_path: File.join(log_dir, "#{name}.log")
        }
      end

      # Mutant runs carry a report path and are classified from the child's
      # report; the baseline suite has none and keeps exit-status semantics.
      def mutant_log_paths(mutant)
        log_paths = scenario_log_paths(mutant_log_name(mutant))
        log_paths.merge(report_path: log_paths[:log_path].sub(/\.log\z/, ".report.json"))
      end

      def build_result(wait_result, log_paths)
        stdout = scenario_log_support.read_log_file(log_paths[:stdout_path])
        stderr = scenario_log_support.read_log_file(log_paths[:stderr_path])
        scenario_log_support.write_combined_log(log_paths[:log_path], stdout, stderr)
        output = { stdout:, stderr:, log_path: log_paths[:log_path] }
        return ScenarioExecutionResult.build(wait_result:, **output) unless log_paths.key?(:report_path)

        report = child_report_store.read(log_paths[:report_path])
        ScenarioExecutionResult.build_for_mutant(wait_result:, report:, **output)
      end

      def run_in_child(mutant:, test_files:, log_paths:)
        Thread.report_on_exception = false
        with_subprocess_env do
          suppress_simplecov!
          suppress_coverage!
          install_debug_timeout_trap if child_debug_log.enabled?
          with_non_interactive_stdin do
            run_child_activation_and_tests(mutant:, test_files:, log_paths:)
          end
        end
      end

      def mutant_log_name(mutant)
        "mutant-#{mutant.id}"
      end

      private

      def run_child_activation_and_tests(mutant:, test_files:, log_paths:)
        report = ->(data) { child_report_store.write(log_paths[:report_path], data) }
        scenario_log_support.with_coverage_dir(mutant.id) do
          scenario_log_support.capture_child_output(log_paths) do
            next 2 unless activate_in_child(mutant, test_files, report)

            run_tests_in_child(test_files, report)
          end
        end
      end

      # Any failure to put the mutant in place is a harness outcome: the tests
      # never ran against the mutation, so nothing may count as a kill.
      def activate_in_child(mutant, test_files, report)
        return true unless activate_with_debug_log(mutant, test_files) == :compile_error

        report.call("outcome" => "activation_failed", "reason" => "the activation source does not compile")
        false
      rescue StandardError, ScriptError => e
        warn "henitai: mutant activation failed: #{e.class}: #{e.message}"
        report.call("outcome" => "activation_failed", "reason" => "#{e.class}: #{e.message}")
        false
      end

      def activate_with_debug_log(mutant, test_files)
        log = child_debug_log
        log.mutant_meta(mutant)
        log.activation_start(mutant.id)
        activation_result = Mutant::Activator.activate!(mutant)
        log.activation_check
        log.activation_end(activation_result, test_files:)
        activation_result
      end

      # RSpec and Minitest let SystemExit through by design. Raised by the
      # code under test it ends the run midway, so it is reported instead of
      # becoming the child's exit status.
      def run_tests_in_child(test_files, report)
        exit_code = run_tests(test_files)
        report.call("outcome" => "tests_finished", "exit_code" => exit_code)
        exit_code
      rescue SystemExit => e
        report.call("outcome" => "system_exit", "status" => e.status)
        1
      end
    end
  end
end
