# frozen_string_literal: true

require_relative "child_debug_log"
require_relative "rspec_file_order"

module Henitai
  module Integration
    # Runs RSpec in-process inside the mutant child (ADR-13).
    #
    # Owns building and configuring a runner, loading the spec files, ordering
    # the example groups the way the parent asked for, and the after-load hook
    # that activates the mutant. Public so its behavior is reachable without a
    # real fork; the integration delegates to it.
    #
    # It also owns the fork-server boot (ADR-15). #preload loads the union of a
    # run's spec files once and returns the runner holding them; the fork server
    # keeps that object, and every forked mutant process inherits it and runs
    # only its own files. The boot therefore lives in the object that also runs
    # the tests, so "am I running from a booted environment" has exactly one
    # owner: this class. There is no mode argument and no state on the
    # integration to get out of step with the runner.
    class RspecChildRunner
      # A spec file failed to load, so no example can run against the mutant.
      class PreloadError < StandardError; end

      # The runner a fork-server boot created. A forked mutant process narrows
      # its example groups to the files it was asked to run.
      class Preloaded < RspecChildRunner; end

      def initialize(log: ChildDebugLog.new, preloaded_runner: nil)
        @log = log
        @preloaded_runner = preloaded_runner
      end

      # True when a fork-server boot supplied this runner, so its example groups
      # hold the union of a run's spec files rather than a single mutant's.
      def preloaded? = !@preloaded_runner.nil?

      # Boots the environment for the fork server: builds and configures an
      # RSpec runner and loads +test_files+ into the process, without running
      # any of them.
      #
      # @raise [PreloadError] when a spec file failed to load
      # @return [Preloaded] the runner every forked mutant process reuses
      def preload(test_files)
        booted = build_runner
        load_spec_files(test_files)
        raise PreloadError, "the spec files failed to load" unless rspec_loaded_cleanly?

        Preloaded.new(log: @log, preloaded_runner: booted)
      end

      # @param test_files [Array<String>] spec files to run
      # @yield [ ] after the spec files load, before any example runs; a falsy
      #   result skips the run (see MutantRunSupport#run_tests_in_child)
      # @return [Integer] RSpec's exit status, or 1 when the run was skipped
      def run(test_files, &after_load)
        runner = environment(test_files)
        return 1 unless ready_to_run?(after_load)

        run_specs(runner, example_groups_to_run(test_files))
      rescue SystemExit => e
        @log.write("[henitai-debug-child] runner_run_system_exit status=#{e.status.inspect}")
        raise
      ensure
        @log.write("[henitai-debug-child] runner_run_ensure")
      end

      # True while no spec file has failed to load; RSpec records such a
      # failure and quits before running anything.
      def rspec_loaded_cleanly?
        world = ::RSpec.world
        !(world.wants_to_quit || world.rspec_is_quitting)
      end

      protected

      # The spec files must be loaded before the gate is consulted: a load
      # failure is what sets the quit flag the gate reads. A booted runner
      # already did this inside the fork server, so loading again would run
      # every example twice.
      def environment(test_files)
        return @preloaded_runner if preloaded?

        prepare(test_files)
      end

      def prepare(test_files)
        runner = build_runner
        load_spec_files(test_files)
        runner
      end

      def build_runner
        @log.write("[henitai-debug-child] build_rspec_runner_start")
        runner = new_runner
        @log.write("[henitai-debug-child] build_rspec_runner_return")
        @log.write("[henitai-debug-child] configure_rspec_runner_start")
        configure_runner(runner)
        @log.write("[henitai-debug-child] configure_rspec_runner_return")
        runner
      end

      def new_runner
        # @type var empty_args: Array[String]
        empty_args = []
        ::RSpec::Core::Runner.__send__(:new, ::RSpec::Core::ConfigurationOptions.new(empty_args))
      end

      def configure_runner(runner)
        @log.write("[henitai-debug-child] trap_interrupt_start")
        ::RSpec::Core::Runner.__send__(:trap_interrupt)
        @log.write("[henitai-debug-child] trap_interrupt_return")
        @log.write("[henitai-debug-child] runner_configure_start")
        runner.send(:configure, $stderr, $stdout)
        @log.write("[henitai-debug-child] runner_configure_return")
      end

      def load_spec_files(test_files)
        @log.write("[henitai-debug-child] load_spec_files_start")
        ::RSpec.configuration.files_to_run = test_files.map { |file| File.expand_path(file) }
        ::RSpec.configuration.load_spec_files
        @log.example_count("after_load")
        @log.write("[henitai-debug-child] load_spec_files_return")
      end

      private

      # A fork-server process loaded the union of the run's spec files; each
      # mutant process runs only the groups defined in its own files.
      # The groups run in the order of test_files, so the child's fail-fast
      # stops at the file the parent expects to fail first, whatever RSpec's
      # random ordering did to the top-level groups.
      def example_groups_to_run(test_files)
        groups = ::RSpec.world.ordered_example_groups
        groups = filter_to_wanted_files(groups, test_files) if preloaded?
        RspecFileOrder.new(test_files).sort(groups)
      end

      def filter_to_wanted_files(groups, test_files)
        wanted = test_files.map { |file| File.expand_path(file) }
        groups.select { |group| wanted.include?(RspecFileOrder.file_of(group)) }
      end

      # The after-load hook (mutant activation) runs only when every spec file
      # loaded; a falsy hook result also skips the run.
      def ready_to_run?(after_load)
        rspec_loaded_cleanly? && (after_load.nil? || after_load.call)
      end

      # One failing example kills the mutant, so the run stops there. Set
      # after the spec files loaded, so a project's own fail_fast setting
      # cannot turn it off.
      def run_specs(runner, example_groups)
        ::RSpec.configuration.fail_fast = 1
        @log.write("[henitai-debug-child] run_specs_start")
        result = runner.send(:run_specs, example_groups)
        @log.write("[henitai-debug-child] run_specs_return result=#{result.inspect}")
        result
      end
    end
  end
end
