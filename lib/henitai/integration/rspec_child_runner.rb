# frozen_string_literal: true

module Henitai
  module Integration
    # Drives an in-process RSpec run inside the mutant child. Kept separate
    # from the framework-agnostic debug helpers so the RSpec-specific runner
    # wiring stays in one place.
    module RspecChildRunner
      private

      def run_rspec_runner(test_files)
        debug_child_puts("[henitai-debug-child] build_rspec_runner_start")
        runner = build_rspec_runner
        debug_child_puts("[henitai-debug-child] build_rspec_runner_return")
        debug_child_puts("[henitai-debug-child] configure_rspec_runner_start")
        configure_rspec_runner(runner)
        debug_child_puts("[henitai-debug-child] configure_rspec_runner_return")
        load_rspec_spec_files(test_files)
        run_rspec_specs(runner)
      rescue SystemExit => e
        debug_child_puts("[henitai-debug-child] runner_run_system_exit status=#{e.status.inspect}")
        raise
      ensure
        debug_child_puts("[henitai-debug-child] runner_run_ensure")
      end

      def build_rspec_runner
        # @type var empty_args: Array[String]
        empty_args = []
        configuration_options = ::RSpec::Core.const_get(:ConfigurationOptions).new(empty_args)
        ::RSpec::Core::Runner.__send__(:new, configuration_options)
      end

      def configure_rspec_runner(runner)
        debug_child_puts("[henitai-debug-child] trap_interrupt_start")
        ::RSpec::Core::Runner.__send__(:trap_interrupt)
        debug_child_puts("[henitai-debug-child] trap_interrupt_return")
        debug_child_puts("[henitai-debug-child] runner_configure_start")
        runner.send(:configure, $stderr, $stdout)
        debug_child_puts("[henitai-debug-child] runner_configure_return")
      end

      def load_rspec_spec_files(test_files)
        debug_child_puts("[henitai-debug-child] load_spec_files_start")
        ::RSpec.configuration.files_to_run = test_files.map do |file|
          File.expand_path(file)
        end
        ::RSpec.configuration.load_spec_files
        debug_child_example_count("after_load")
        debug_child_puts("[henitai-debug-child] load_spec_files_return")
      end

      def run_rspec_specs(runner)
        debug_child_puts("[henitai-debug-child] run_specs_start")
        result = runner.send(:run_specs, ::RSpec.world.ordered_example_groups)
        debug_child_puts("[henitai-debug-child] run_specs_return result=#{result.inspect}")
        result
      end
    end
  end
end
