# frozen_string_literal: true

require "stringio"
require_relative "../process_wakeup"
require_relative "child_debug_support"
require_relative "child_runtime_control"
require_relative "rspec_child_runner"
require_relative "scenario_log_support"

module Henitai
  module Integration
    # Base class for all integrations.
    class Base
      include ChildDebugSupport
      include ChildRuntimeControl
      include RspecChildRunner

      # @param subject [Subject]
      # @return [Array<String>] paths to test files that cover this subject
      def select_tests(subject)
        raise NotImplementedError
      end

      # @return [Array<String>] all test files for the configured framework
      def test_files
        raise NotImplementedError
      end

      # Run test files in a child process with the mutant active.
      #
      # @param mutant [Mutant]
      # @param test_files [Array<String>]
      # @param timeout [Float] seconds
      # @return [ScenarioExecutionResult]
      def run_mutant(mutant:, test_files:, timeout:)
        raise NotImplementedError
      end

      # Fork a child process for the mutant without waiting for it to finish.
      # Returns a ChildHandle carrying the OS pid and log file paths.
      # The caller is responsible for waiting and cleanup.
      #
      # @param mutant [Mutant]
      # @param test_files [Array<String>]
      # @return [RspecProcessRunner::ChildHandle]
      def spawn_mutant(mutant:, test_files:)
        raise NotImplementedError
      end

      def per_test_coverage_supported?
        false
      end

      def wait_with_timeout(pid, timeout)
        wakeup = Henitai.const_get(:ProcessWakeup).new.install
        return Process.last_status if wait_nonblocking(pid)

        wakeup.wait(timeout)
        wakeup.drain
        return Process.last_status if wait_nonblocking(pid)
        return Process.last_status if wait_nonblocking(pid)

        handle_timeout(pid)
      ensure
        wakeup&.close
      end

      def reap_child(pid)
        Process.wait(pid)
      rescue Errno::ECHILD, Errno::ESRCH
        nil
      end

      def cleanup_process_group(pid)
        grace_period = 2.0
        wakeup = Henitai.const_get(:ProcessWakeup).new.install
        Process.kill(:SIGTERM, -pid)
        return if wait_nonblocking(pid)

        wakeup.wait(grace_period)
        wakeup.drain
        return if wait_nonblocking(pid)

        Process.kill(:SIGKILL, -pid)
      rescue Errno::EPERM
        cleanup_child_process(pid)
      rescue Errno::ESRCH
        nil
      ensure
        wakeup&.close
      end

      private

      def pause(seconds)
        sleep(seconds)
      end

      def handle_timeout(pid)
        begin
          debug_child_timeout_dump(pid)
          cleanup_process_group(pid)
        ensure
          reap_child(pid)
        end
        :timeout
      end

      def cleanup_child_process(pid)
        grace_period = 2.0
        wakeup = Henitai.const_get(:ProcessWakeup).new.install
        Process.kill(:SIGTERM, pid)
        return if wait_nonblocking(pid)

        wakeup.wait(grace_period)
        wakeup.drain
        return if wait_nonblocking(pid)

        Process.kill(:SIGKILL, pid)
      rescue Errno::EPERM, Errno::ESRCH
        nil
      ensure
        wakeup&.close
      end

      def subprocess_env
        { "PARALLEL_WORKERS" => "1" }
      end

      def wait_nonblocking(pid)
        Process.wait(pid, Process::WNOHANG)
      rescue Errno::ECHILD, Errno::ESRCH
        nil
      end

      def scenario_log_support
        @scenario_log_support ||= ScenarioLogSupport.new
      end

      def with_subprocess_env
        original_env = {} # : Hash[String, String?]
        subprocess_env.each do |key, value|
          original_env[key] = ENV.fetch(key, nil)
          ENV[key] = value
        end
        yield
      ensure
        restore_subprocess_env(original_env)
      end

      def restore_subprocess_env(original_env)
        original_env.each do |key, value|
          if value.nil?
            ENV.delete(key)
          else
            ENV[key] = value
          end
        end
      end

      def with_non_interactive_stdin
        original_stdin = $stdin
        $stdin = StringIO.new
        yield
      ensure
        $stdin = original_stdin
      end

      def run_tests(test_files)
        require "rspec/core"
        ::RSpec.__send__(:configuration).fail_if_no_examples = true
        debug_child_rspec_trace(test_files:, rspec_options: [], rspec_argv: test_files)
        debug_child_example_count("before_run") # steep:ignore Ruby::NoMethod
        debug_child_puts("[henitai-debug-child] runner_run_start")
        status = run_rspec_runner(test_files)
        debug_child_puts("[henitai-debug-child] runner_run_return status=#{status.inspect}")
        debug_child_example_count("after_run") # steep:ignore Ruby::NoMethod
        debug_child_rspec_exit(status)
        return status if status.is_a?(Integer)

        status == true ? 0 : 1
      end

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
