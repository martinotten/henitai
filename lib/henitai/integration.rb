# frozen_string_literal: true

require "fileutils"
require "stringio"
require_relative "process_wakeup"
require_relative "integration/rspec_process_runner"
require_relative "integration/scenario_log_support"
require_relative "integration/coverage_suppression"
require_relative "integration/child_debug_support"
require_relative "integration/base"
require_relative "integration/rspec_test_selection"

module Henitai
  # Namespace for test-framework integrations.
  #
  # An Integration is responsible for:
  #   1. Discovering test files relevant to a Subject (test selection)
  #   2. Running the selected tests in a child process with a mutant injected
  #   3. Reporting pass/fail/timeout to the runner
  #
  # Test selection uses longest-prefix matching:
  #   Subject expression "Foo::Bar#method" matches example groups whose
  #   description contains "Foo::Bar" or "Foo::Bar#method".
  #
  # Built-in integrations:
  #   rspec  — RSpec 3.x
  module Integration
    # Integration adapter for RSpec.
    #
    # This class exists as the stable public entry point for the RSpec
    # integration, even though the concrete behavior is not implemented yet.
    # @param name [String] integration name, e.g. "rspec"
    # @return [Class] integration class
    def self.for(name)
      const_get(name.capitalize)
    rescue NameError
      available = constants.filter_map do |constant_name|
        integration = const_get(constant_name)
        constant_name.to_s.downcase if integration.is_a?(Class) && integration < Base
      end.sort.join(", ")

      raise ArgumentError, "Unknown integration: #{name}. Available: #{available}"
    end

    # RSpec integration adapter.
    class Rspec < Base
      include RspecTestSelection

      DEFAULT_SUITE_TIMEOUT = 300.0

      def test_files = spec_files

      def spawn_mutant(mutant:, test_files:)
        log_paths = scenario_log_paths(mutant_log_name(mutant))
        RspecProcessRunner.new.spawn_mutant(self, mutant:, test_files:, log_paths:)
      end

      def run_mutant(mutant:, test_files:, timeout:)
        RspecProcessRunner.new.run_mutant(self, mutant:, test_files:, timeout:)
      end

      def per_test_coverage_supported?
        true
      end

      def run_suite(test_files, timeout: DEFAULT_SUITE_TIMEOUT)
        RspecProcessRunner.new.run_suite(self, test_files, timeout:)
      end

      def suite_command(test_files)
        [
          "bundle", "exec", "ruby",
          "-r", "henitai/rspec_coverage_formatter",
          "-e", rspec_suite_runner_script,
          *test_files
        ]
      end

      def rspec_suite_runner_script
        <<~RUBY
          require "rspec/core"

          test_files = ARGV.map { |file| File.expand_path(file) }
          config = RSpec.configuration
          options = RSpec::Core::ConfigurationOptions.new(
            ["--format", "progress", "--format", "Henitai::CoverageFormatter"]
          )
          runner = RSpec::Core::Runner.send(:new, options)

          RSpec::Core::Runner.send(:trap_interrupt)
          runner.send(:configure, $stderr, $stdout)
          config.files_to_run = test_files
          config.load_spec_files

          status = runner.send(:run_specs, RSpec.world.ordered_example_groups)
          exit(status.is_a?(Integer) ? status : (status == true ? 0 : 1))
        RUBY
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

      def spawn_suite_process(test_files, log_paths)
        File.open(log_paths[:stdout_path], "w") do |stdout_file|
          File.open(log_paths[:stderr_path], "w") do |stderr_file|
            Process.spawn(
              subprocess_env,
              *suite_command(test_files),
              out: stdout_file,
              err: stderr_file,
              pgroup: true
            )
          end
        end
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
    end
  end
end

require_relative "integration/minitest"
