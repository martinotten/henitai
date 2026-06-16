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
      def spawn_mutant(mutant:, test_files:)
        log_paths = scenario_log_paths(mutant_log_name(mutant))
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

      def build_result(wait_result, log_paths)
        stdout = read_log_file(log_paths[:stdout_path])
        stderr = read_log_file(log_paths[:stderr_path])
        write_combined_log(log_paths[:log_path], stdout, stderr)

        ScenarioExecutionResult.build(
          wait_result:,
          stdout:,
          stderr:,
          log_path: log_paths[:log_path]
        )
      end

      def run_in_child(mutant:, test_files:, log_paths:)
        Thread.report_on_exception = false
        with_subprocess_env do
          suppress_simplecov!
          suppress_coverage!
          install_debug_timeout_trap if debug_child?
          with_non_interactive_stdin do
            run_child_activation_and_tests(mutant:, test_files:, log_paths:)
          end
        end
      end

      def mutant_log_name(mutant)
        "mutant-#{mutant.id}"
      end

      def read_log_file(path)
        return "" unless File.exist?(path)

        File.read(path)
      end

      def write_combined_log(path, stdout, stderr)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, combined_log(stdout, stderr))
      end

      def combined_log(stdout, stderr)
        [
          (stdout.empty? ? nil : "stdout:\n#{stdout}"),
          (stderr.empty? ? nil : "stderr:\n#{stderr}")
        ].compact.join("\n")
      end

      private

      def run_child_activation_and_tests(mutant:, test_files:, log_paths:)
        scenario_log_support.with_coverage_dir(mutant.id) do
          scenario_log_support.capture_child_output(log_paths) do
            debug_child_mutant_meta(mutant) if debug_child?
            debug_child_activation_start(mutant.id)
            activation_result = Mutant::Activator.activate!(mutant)
            debug_child_activation_check if debug_child?
            debug_child_activation_end(activation_result, test_files:)
            activation_result == :compile_error ? 2 : run_tests(test_files)
          end
        end
      end
    end
  end
end
