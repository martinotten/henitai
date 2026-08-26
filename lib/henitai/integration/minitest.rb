# frozen_string_literal: true

require "fileutils"
# Guarded to avoid a circular require: integration.rb requires this file at its
# tail, by which point Base is already defined, so the require is skipped.
require_relative "../integration" unless defined?(Henitai::Integration::Base)
require_relative "minitest_load_path"
require_relative "minitest_suite_command"
require_relative "minitest_test_runner"
require_relative "rails_environment_preloader"

module Henitai
  module Integration
    # Minitest integration adapter.
    #
    # A sibling of Rspec behind Base: it shares the framework-agnostic mutant-run
    # orchestration (MutantRunSupport) and test selection (RspecTestSelection)
    # but implements its own Minitest-specific test invocation and suite command.
    # Per-test coverage collection is not yet wired into this path.
    class Minitest < Base
      include MutantRunSupport
      include RspecTestSelection

      DEFAULT_SUITE_TIMEOUT = 300.0

      def test_files = spec_files

      def per_test_coverage_supported?
        true
      end

      def run_mutant(mutant:, test_files:, timeout:)
        MinitestLoadPath.ensure!
        super
      end

      def spawn_mutant(mutant:, test_files:)
        MinitestLoadPath.ensure!
        super
      end

      def run_in_child(mutant:, test_files:, log_paths:)
        ENV["RAILS_ENV"] = "test" unless ENV["RAILS_ENV"] == "test"
        RailsEnvironmentPreloader.new.call
        super
      end

      def run_suite(test_files, timeout: DEFAULT_SUITE_TIMEOUT)
        log_paths = scenario_log_paths("baseline")
        pid = spawn_suite_process(test_files, log_paths)
        wait_result = wait_with_timeout(pid, timeout)
        build_result(wait_result, log_paths)
      ensure
        cleanup_suite_process(pid, wait_result)
      end

      def suite_command(test_files)
        MinitestSuiteCommand.new.build(test_files)
      end

      private

      def run_tests(test_files)
        MinitestTestRunner.new.call(test_files)
      end

      def subprocess_env
        env = super
        env["RAILS_ENV"] = "test" unless ENV["RAILS_ENV"] == "test"
        env["PARALLEL_WORKERS"] = "1"
        env
      end

      # `pgroup: true` makes the suite child a group leader, so the whole tree
      # it spawns -- a Rails test server, browser drivers -- is signalable as
      # one group. Without it the parent's `kill(:SIGTERM, -pid)` addresses a
      # group that does not exist, raises ESRCH, and leaves a timed-out suite
      # running to completion while the parent has already given up on it.
      def spawn_suite_process(test_files, log_paths)
        FileUtils.mkdir_p(File.dirname(log_paths[:stdout_path]))
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

      # A timeout has already torn the group down and reaped the child in
      # `handle_timeout`; signalling again would only race a recycled pid.
      def cleanup_suite_process(pid, wait_result)
        return unless pid

        cleanup_process_group(pid) unless wait_result == :timeout
        reap_child(pid) if wait_result.nil?
      end

      def spec_files
        (Dir.glob("test/**/*_test.rb") + Dir.glob("test/**/*_spec.rb"))
          .reject { |f| f.start_with?("test/system/") }
      end
    end
  end
end
