# frozen_string_literal: true

require "fileutils"
require "stringio"
require_relative "process_wakeup"
require_relative "integration/child_bootstrap"
require_relative "integration/rspec_process_runner"
require_relative "integration/scenario_log_support"
require_relative "integration/coverage_suppression"
require_relative "integration/child_debug_log"
require_relative "integration/loaded_features"
require_relative "integration/base"
require_relative "integration/mutant_run_support"
require_relative "integration/rspec_child_runner"
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
      include MutantRunSupport
      include RspecChildRunner
      include RspecTestSelection

      DEFAULT_SUITE_TIMEOUT = 300.0

      def test_files = spec_files

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

      private

      def run_tests(test_files)
        require "rspec/core"
        ::RSpec.__send__(:configuration).fail_if_no_examples = true
        log = child_debug_log
        log.rspec_trace(test_files:, rspec_options: [], rspec_argv: test_files)
        log.example_count("before_run")
        log.write("[henitai-debug-child] runner_run_start")
        status = run_rspec_runner(test_files)
        log.write("[henitai-debug-child] runner_run_return status=#{status.inspect}")
        log.example_count("after_run")
        log.rspec_exit(status)
        return status if status.is_a?(Integer)

        status == true ? 0 : 1
      end
    end
  end
end

require_relative "integration/minitest"
