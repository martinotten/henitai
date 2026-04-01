# frozen_string_literal: true

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
      raise ArgumentError, "Unknown integration: #{name}. Available: rspec"
    end

    # Base class for all integrations.
    class Base
      # @param subject [Subject]
      # @return [Array<String>] paths to test files that cover this subject
      def select_tests(subject)
        raise NotImplementedError
      end

      # Run test files in a child process with the mutant active.
      # Returns :killed, :survived, or :timeout.
      #
      # @param mutant    [Mutant]
      # @param test_files [Array<String>]
      # @param timeout   [Float] seconds
      # @return [Symbol]
      def run_mutant(mutant:, test_files:, timeout:)
        raise NotImplementedError
      end
    end

    # RSpec integration adapter.
    class Rspec < Base
      def select_tests(subject)
        raise NotImplementedError
      end

      def run_mutant(mutant:, test_files:, timeout:)
        pid = Process.fork do
          ENV["HENITAI_MUTANT_ID"] = mutant.id
          Process.exit(run_in_child(mutant:, test_files:))
        end

        wait_with_timeout(pid, timeout)
      end

      private

      def run_in_child(mutant:, test_files:)
        activate_mutant(mutant)
        run_tests(test_files)
      end

      def wait_with_timeout(pid, timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

        loop do
          return classify_exit_status(Process.last_status) if Process.wait(pid, Process::WNOHANG)
          return handle_timeout(pid) if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          pause(0.01)
        end
      end

      def handle_timeout(pid)
        Process.kill(:SIGTERM, pid)
        pause(2.0)
        Process.kill(:SIGKILL, pid)
        :timeout
      end

      def activate_mutant(mutant)
        mutant.id
      end

      def run_tests(test_files)
        RSpec::Core::Runner.run(test_files) ? 0 : 1
      end

      def pause(seconds)
        sleep(seconds)
      end

      def classify_exit_status(status)
        status.success? ? :survived : :killed
      end
    end
  end
end
