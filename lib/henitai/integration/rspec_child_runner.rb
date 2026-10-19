# frozen_string_literal: true

module Henitai
  module Integration
    # Drives an in-process RSpec run inside the mutant child. Kept separate
    # from the framework-agnostic debug helpers so the RSpec-specific runner
    # wiring stays in one place.
    module RspecChildRunner
      private

      def run_rspec_runner(test_files, &after_load)
        log = child_debug_log
        runner = @preloaded_runner || prepare_rspec_runner(test_files)
        return 1 unless ready_to_run?(after_load)

        run_rspec_specs(runner, example_groups_to_run(test_files))
      rescue SystemExit => e
        log.write("[henitai-debug-child] runner_run_system_exit status=#{e.status.inspect}")
        raise
      ensure
        child_debug_log.write("[henitai-debug-child] runner_run_ensure")
      end

      def prepare_rspec_runner(test_files)
        log = child_debug_log
        log.write("[henitai-debug-child] build_rspec_runner_start")
        runner = build_rspec_runner
        log.write("[henitai-debug-child] build_rspec_runner_return")
        log.write("[henitai-debug-child] configure_rspec_runner_start")
        configure_rspec_runner(runner)
        log.write("[henitai-debug-child] configure_rspec_runner_return")
        load_rspec_spec_files(test_files)
        runner
      end

      # A fork-server process loaded the union of the run's spec files; each
      # mutant process runs only the groups defined in its own files.
      def example_groups_to_run(test_files)
        groups = ::RSpec.world.ordered_example_groups
        return groups unless @preloaded_runner

        wanted = test_files.map { |file| File.expand_path(file) }
        groups.select { |group| wanted.include?(example_group_file(group)) }
      end

      def example_group_file(group)
        metadata = group.metadata
        metadata[:absolute_file_path] || File.expand_path(metadata[:file_path])
      end

      # The after-load hook (mutant activation) runs only when every spec file
      # loaded; a falsy hook result also skips the run.
      def ready_to_run?(after_load)
        rspec_loaded_cleanly? && (after_load.nil? || after_load.call)
      end

      # RSpec records a spec file that failed to load and quits before running.
      def rspec_loaded_cleanly?
        world = ::RSpec.world
        !(world.wants_to_quit || world.rspec_is_quitting)
      end

      def build_rspec_runner
        # @type var empty_args: Array[String]
        empty_args = []
        configuration_options = ::RSpec::Core.const_get(:ConfigurationOptions).new(empty_args)
        ::RSpec::Core::Runner.__send__(:new, configuration_options)
      end

      def configure_rspec_runner(runner)
        child_debug_log.write("[henitai-debug-child] trap_interrupt_start")
        ::RSpec::Core::Runner.__send__(:trap_interrupt)
        child_debug_log.write("[henitai-debug-child] trap_interrupt_return")
        child_debug_log.write("[henitai-debug-child] runner_configure_start")
        runner.send(:configure, $stderr, $stdout)
        child_debug_log.write("[henitai-debug-child] runner_configure_return")
      end

      def load_rspec_spec_files(test_files)
        child_debug_log.write("[henitai-debug-child] load_spec_files_start")
        ::RSpec.configuration.files_to_run = test_files.map do |file|
          File.expand_path(file)
        end
        ::RSpec.configuration.load_spec_files
        child_debug_log.example_count("after_load")
        child_debug_log.write("[henitai-debug-child] load_spec_files_return")
      end

      def run_rspec_specs(runner, example_groups)
        child_debug_log.write("[henitai-debug-child] run_specs_start")
        result = runner.send(:run_specs, example_groups)
        child_debug_log.write("[henitai-debug-child] run_specs_return result=#{result.inspect}")
        result
      end
    end
  end
end
