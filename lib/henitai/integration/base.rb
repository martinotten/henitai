# frozen_string_literal: true

require "stringio"
require_relative "../process_wakeup"
require_relative "child_debug_log"
require_relative "child_runtime_control"
require_relative "scenario_log_support"

module Henitai
  module Integration
    # Base class for all integrations. Provides the framework-agnostic child
    # process lifecycle (wait, timeout handling, cleanup) and subprocess
    # environment helpers. Concrete adapters mix in MutantRunSupport and
    # implement #run_tests plus test selection.
    class Base
      include ChildRuntimeControl

      EXITED_GROUP_POLL_INTERVAL = 0.05
      EXITED_GROUP_POLL_COUNT = 40

      # Child-run diagnostics. Public so the child-side modules mixed into
      # concrete adapters can reach it without `send`.
      def child_debug_log
        @child_debug_log ||= ChildDebugLog.new
      end

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

      # True when the integration can boot once in a fork server (ADR-15) and
      # run mutants from the booted state.
      def fork_server_supported?
        false
      end

      # Loads the test environment and the given test files without running
      # anything; only called inside the fork server process.
      #
      # @param test_files [Array<String>]
      def preload_environment(test_files)
        raise NotImplementedError
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
        if leader_exited?(pid)
          terminate_exited_group(pid)
        else
          terminate_running_group(pid)
        end
      rescue Errno::EPERM
        cleanup_child_process(pid)
      rescue Errno::ESRCH
        nil
      end

      private

      # A leader that already exited normally cannot be waited on again, so
      # the group is polled for members instead of burning the grace period.
      def terminate_exited_group(pid)
        Process.kill(:SIGTERM, -pid)
        return unless group_members_remain?(pid)

        Process.kill(:SIGKILL, -pid)
      end

      def terminate_running_group(pid)
        grace_period = 2.0
        wakeup = Henitai.const_get(:ProcessWakeup).new.install
        Process.kill(:SIGTERM, -pid)
        return if wait_nonblocking(pid)

        wakeup.wait(grace_period)
        wakeup.drain
        return if wait_nonblocking(pid)

        Process.kill(:SIGKILL, -pid)
      ensure
        wakeup&.close
      end

      def leader_exited?(pid)
        !Process.wait(pid, Process::WNOHANG).nil?
      rescue Errno::ECHILD, Errno::ESRCH
        true
      end

      def group_members_remain?(pid)
        EXITED_GROUP_POLL_COUNT.times do
          return false unless group_alive?(pid)

          pause(EXITED_GROUP_POLL_INTERVAL)
        end
        group_alive?(pid)
      end

      # Signal 0 probes existence only: ESRCH means the group is empty.
      def group_alive?(pid)
        Process.kill(0, -pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

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

      def suite_process_env
        subprocess_env.merge(SuiteBootClock::STARTED_AT_ENV => Time.now.to_f.to_s)
      end

      def wait_nonblocking(pid)
        Process.wait(pid, Process::WNOHANG)
      rescue Errno::ECHILD, Errno::ESRCH
        nil
      end

      def scenario_log_support
        @scenario_log_support ||= ScenarioLogSupport.new
      end

      def child_report_store
        @child_report_store ||= ChildReportStore.new
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
    end
  end
end
