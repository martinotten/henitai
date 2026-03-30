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

    class Rspec < Base
      def select_tests(subject)
        raise NotImplementedError
      end

      def run_mutant(mutant:, test_files:, timeout:)
        raise NotImplementedError
      end
    end
  end
end
