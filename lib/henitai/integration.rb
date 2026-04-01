# frozen_string_literal: true

require "minitest"
require "rspec/core"

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
      REQUIRE_DIRECTIVE_PATTERN = /
        \A\s*
        (require|require_relative)
        \s*
        (?:\(\s*)?
        ["']([^"']+)["']
        \s*\)?
      /x

      def select_tests(subject)
        matches = spec_files.select do |path|
          content = File.read(path)
          selection_patterns(subject).any? { |pattern| content.include?(pattern) }
        rescue StandardError
          false
        end

        return matches unless matches.empty?

        fallback_spec_files(subject)
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
        Mutant::Activator.activate!(mutant)
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
        begin
          Process.kill(:SIGTERM, pid)
          pause(2.0)
          Process.kill(:SIGKILL, pid)
        rescue Errno::ESRCH
          # The child may exit after SIGTERM but before SIGKILL.
        ensure
          reap_child(pid)
        end
        :timeout
      end

      def run_tests(test_files)
        status = RSpec::Core::Runner.run(test_files + rspec_options)
        return status if status.is_a?(Integer)

        status == true ? 0 : 1
      end

      def pause(seconds)
        sleep(seconds)
      end

      def classify_exit_status(status)
        status.success? ? :survived : :killed
      end

      def rspec_options
        ["--require", "henitai/coverage_formatter"]
      end

      def spec_files
        Dir.glob("spec/**/*_spec.rb")
      end

      def fallback_spec_files(subject)
        return [] unless subject.source_file

        matches = spec_files.select do |path|
          requires_source_file_transitively?(path, subject.source_file)
        rescue StandardError
          false
        end

        matches.empty? ? spec_files : matches
      end

      def selection_patterns(subject)
        [
          subject.expression,
          subject.namespace
        ].compact.uniq.sort_by(&:length).reverse
      end

      def requires_source_file?(spec_file, source_file)
        content = File.read(spec_file)
        basename = File.basename(source_file, ".rb")
        content.include?(basename) || content.include?(source_file)
      end

      def requires_source_file_transitively?(spec_file, source_file, visited = [])
        normalized_spec_file = File.expand_path(spec_file)
        return false if visited.include?(normalized_spec_file)

        visited << normalized_spec_file
        return true if requires_source_file?(spec_file, source_file)

        required_files(spec_file).any? do |required_file|
          requires_source_file_transitively?(required_file, source_file, visited)
        end
      end

      def required_files(spec_file)
        File.read(spec_file).lines.filter_map do |line|
          match = line.match(REQUIRE_DIRECTIVE_PATTERN)
          next unless match

          resolve_required_file(spec_file, match[1].to_s, match[2].to_s)
        end
      end

      def resolve_required_file(spec_file, method_name, required_path)
        candidates =
          if method_name == "require_relative"
            relative_candidates(spec_file, required_path)
          else
            require_candidates(spec_file, required_path)
          end

        candidates.find { |candidate| File.file?(candidate) }
      end

      def relative_candidates(spec_file, required_path)
        expand_candidates(File.dirname(spec_file), required_path)
      end

      def require_candidates(spec_file, required_path)
        ([File.dirname(spec_file), Dir.pwd] + $LOAD_PATH).flat_map do |base_path|
          expand_candidates(base_path, required_path)
        end
      end

      def expand_candidates(base_path, required_path)
        [
          File.expand_path(required_path, base_path),
          File.expand_path("#{required_path}.rb", base_path)
        ].uniq
      end

      def reap_child(pid)
        Process.wait(pid)
      rescue Errno::ECHILD, Errno::ESRCH
        nil
      end
    end

    # Minitest integration adapter.
    class Minitest < Rspec
      private

      def run_tests(test_files)
        test_files.each { |file| require File.expand_path(file) }
        # @type var empty_args: Array[String]
        empty_args = []
        status = ::Minitest.run(empty_args)
        return status if status.is_a?(Integer)

        status == true ? 0 : 1
      end

      def spec_files
        Dir.glob("test/**/*_test.rb") + Dir.glob("test/**/*_spec.rb")
      end
    end
  end
end
