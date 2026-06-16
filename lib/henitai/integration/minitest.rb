# frozen_string_literal: true

require "fileutils"
# Guarded to avoid a circular require: integration.rb requires this file at its
# tail, by which point Base is already defined, so the require is skipped.
require_relative "../integration" unless defined?(Henitai::Integration::Base)

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
        setup_load_path
        super
      end

      def spawn_mutant(mutant:, test_files:)
        setup_load_path
        super
      end

      def run_in_child(mutant:, test_files:, log_paths:)
        ENV["RAILS_ENV"] = "test" unless ENV["RAILS_ENV"] == "test"
        preload_environment
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

      private

      def suite_command(test_files)
        ["bundle", "exec", "ruby", "-I", "test",
         "-r", "henitai/minitest_simplecov",
         "-r", "henitai/minitest_coverage_hook",
         "-e", "ARGV.each { |f| require File.expand_path(f) }",
         *test_files]
      end

      def run_tests(test_files)
        suppress_simplecov!
        suppress_minitest_autorun!
        test_files.each { |file| require File.expand_path(file) }
        # @type var empty_args: Array[String]
        empty_args = []
        status = ::Minitest.run(empty_args)
        return status if status.is_a?(Integer)

        status == true ? 0 : 1
      end

      def preload_environment
        env_file = File.expand_path("config/environment.rb")
        require env_file if File.exist?(env_file)
      end

      def setup_load_path
        test_dir = File.expand_path("test")
        $LOAD_PATH.unshift(test_dir) unless $LOAD_PATH.include?(test_dir)
      end

      def suppress_minitest_autorun!
        require "minitest"
        singleton_class = ::Minitest.singleton_class
        suppressor = @minitest_autorun_suppressor ||= Module.new.tap do |mod|
          mod.define_method(:autorun) { nil }
        end
        return if singleton_class.ancestors.include?(suppressor)

        singleton_class.prepend(suppressor)
        nil
      rescue LoadError, NameError
        nil
      end

      def subprocess_env
        env = super
        env["RAILS_ENV"] = "test" unless ENV["RAILS_ENV"] == "test"
        env["PARALLEL_WORKERS"] = "1"
        env
      end

      def spawn_suite_process(test_files, log_paths)
        FileUtils.mkdir_p(File.dirname(log_paths[:stdout_path]))
        File.open(log_paths[:stdout_path], "w") do |stdout_file|
          File.open(log_paths[:stderr_path], "w") do |stderr_file|
            Process.spawn(
              subprocess_env,
              *suite_command(test_files),
              out: stdout_file,
              err: stderr_file
            )
          end
        end
      end

      def cleanup_suite_process(pid, wait_result)
        return unless pid

        cleanup_child_process(pid)
        reap_child(pid) if wait_result.nil?
      end

      def spec_files
        (Dir.glob("test/**/*_test.rb") + Dir.glob("test/**/*_spec.rb"))
          .reject { |f| f.start_with?("test/system/") }
      end
    end
  end
end
