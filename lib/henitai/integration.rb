# frozen_string_literal: true

require "fileutils"
require "minitest"

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
    # Shared helpers for capturing stdout/stderr from child test processes.
    class ScenarioLogSupport
      def capture_child_output(log_paths)
        output_files = open_child_output(log_paths)
        yield
      ensure
        close_child_output(output_files)
      end

      def with_coverage_dir(mutant_id)
        original_coverage_dir = ENV.fetch("HENITAI_COVERAGE_DIR", nil)
        ENV["HENITAI_COVERAGE_DIR"] = mutation_coverage_dir(mutant_id)
        yield
      ensure
        if original_coverage_dir.nil?
          ENV.delete("HENITAI_COVERAGE_DIR")
        else
          ENV["HENITAI_COVERAGE_DIR"] = original_coverage_dir
        end
      end

      def open_child_output(log_paths)
        FileUtils.mkdir_p(File.dirname(log_paths[:log_path]))
        output_files = build_child_output_files(log_paths)
        sync_child_output_files(output_files)
        redirect_child_output(output_files)
        output_files
      end

      def close_child_output(output_files)
        return unless output_files

        restore_child_output(output_files)
        close_child_output_files(output_files)
      end

      def build_child_output_files(log_paths)
        {
          original_stdout: $stdout.dup,
          original_stderr: $stderr.dup,
          stdout_file: File.new(log_paths[:stdout_path], "w"),
          stderr_file: File.new(log_paths[:stderr_path], "w")
        }
      end

      def sync_child_output_files(output_files)
        output_files[:stdout_file].sync = true
        output_files[:stderr_file].sync = true
      end

      def redirect_child_output(output_files)
        $stdout.reopen(output_files[:stdout_file])
        $stderr.reopen(output_files[:stderr_file])
      end

      def restore_child_output(output_files)
        reopen_child_output_stream($stdout, output_files[:original_stdout])
        reopen_child_output_stream($stderr, output_files[:original_stderr])
      end

      def reopen_child_output_stream(stream, original_stream)
        stream.reopen(original_stream) if original_stream
      end

      def close_child_output_files(output_files)
        %i[stdout_file stderr_file original_stdout original_stderr].each do |key|
          output_files[key]&.close
        end
      end

      private

      def mutation_coverage_dir(mutant_id)
        reports_dir = ENV.fetch("HENITAI_REPORTS_DIR", "reports")
        File.join(reports_dir, "mutation-coverage", mutant_id.to_s)
      end
    end

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
    end

    # RSpec integration adapter.
    class Rspec < Base
      DEFAULT_SUITE_TIMEOUT = 300.0
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

      def test_files
        spec_files
      end

      def run_mutant(mutant:, test_files:, timeout:)
        log_paths = scenario_log_paths("mutant-#{mutant.id}")
        pid = Process.fork do
          ENV["HENITAI_MUTANT_ID"] = mutant.id
          Process.exit(run_in_child(mutant:, test_files:, log_paths:))
        end

        build_result(wait_with_timeout(pid, timeout), log_paths)
      end

      def run_suite(test_files, timeout: DEFAULT_SUITE_TIMEOUT)
        log_paths = scenario_log_paths("baseline")
        FileUtils.mkdir_p(File.dirname(log_paths[:stdout_path]))
        pid = File.open(log_paths[:stdout_path], "w") do |stdout_file|
          File.open(log_paths[:stderr_path], "w") do |stderr_file|
            Process.spawn(*suite_command(test_files), out: stdout_file, err: stderr_file)
          end
        end
        build_result(wait_with_timeout(pid, timeout), log_paths)
      end

      private

      def run_in_child(mutant:, test_files:, log_paths:)
        scenario_log_support.with_coverage_dir(mutant.id) do
          scenario_log_support.capture_child_output(log_paths) do
            return 2 if Mutant::Activator.activate!(mutant) == :compile_error

            run_tests(test_files)
          end
        end
      end

      def suite_command(test_files)
        ["bundle", "exec", "rspec", *test_files]
      end

      def wait_with_timeout(pid, timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

        loop do
          return Process.last_status if Process.wait(pid, Process::WNOHANG)
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
        require "rspec/core"
        status = RSpec::Core::Runner.run(test_files + rspec_options)
        return status if status.is_a?(Integer)

        status == true ? 0 : 1
      end

      def rspec_options
        ["--require", "henitai/coverage_formatter"]
      end

      def pause(seconds)
        sleep(seconds)
      end

      def scenario_log_support
        @scenario_log_support ||= ScenarioLogSupport.new
      end

      def read_log_file(path)
        return "" unless File.exist?(path)

        File.read(path)
      end

      def write_combined_log(path, stdout, stderr)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, combined_log(stdout, stderr))
      end

      def combined_log(stdout, stderr)
        [
          (stdout.empty? ? nil : "stdout:\n#{stdout}"),
          (stderr.empty? ? nil : "stderr:\n#{stderr}")
        ].compact.join("\n")
      end

      def scenario_log_paths(name)
        reports_dir = ENV.fetch("HENITAI_REPORTS_DIR", "reports")
        log_dir = File.join(reports_dir, "mutation-logs")
        {
          stdout_path: File.join(log_dir, "#{name}.stdout.log"),
          stderr_path: File.join(log_dir, "#{name}.stderr.log"),
          log_path: File.join(log_dir, "#{name}.log")
        }
      end

      def build_result(wait_result, log_paths)
        status = scenario_status(wait_result)
        stdout = read_log_file(log_paths[:stdout_path])
        stderr = read_log_file(log_paths[:stderr_path])
        write_combined_log(log_paths[:log_path], stdout, stderr)

        ScenarioExecutionResult.new(
          status:,
          stdout:,
          stderr:,
          log_path: log_paths[:log_path],
          exit_status: exit_status_for(wait_result)
        )
      end

      def scenario_status(wait_result)
        return :timeout if wait_result == :timeout
        return :compile_error if exit_status_for(wait_result) == 2
        return :survived if wait_result.respond_to?(:success?) && wait_result.success?

        :killed
      end

      def exit_status_for(wait_result)
        return nil if wait_result == :timeout
        return nil unless wait_result.respond_to?(:exitstatus)

        wait_result.exitstatus
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
    #
    # Coverage formatter injection remains implemented in the RSpec child
    # runner. Minitest shares selection and execution semantics, but per-test
    # coverage collection is not yet wired into this path.
    class Minitest < Rspec
      def run_mutant(mutant:, test_files:, timeout:)
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
        FileUtils.mkdir_p(File.dirname(log_paths[:stdout_path]))
        pid = File.open(log_paths[:stdout_path], "w") do |stdout_file|
          File.open(log_paths[:stderr_path], "w") do |stderr_file|
            Process.spawn(subprocess_env, *suite_command(test_files), out: stdout_file, err: stderr_file)
          end
        end
        build_result(wait_with_timeout(pid, timeout), log_paths)
      end

      private

      def suite_command(test_files)
        ["bundle", "exec", "ruby", "-I", "test",
         "-r", "henitai/minitest_simplecov",
         "-e", "ARGV.each { |f| require File.expand_path(f) }",
         *test_files]
      end

      def run_tests(test_files)
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

      def subprocess_env
        env = {}
        env["RAILS_ENV"] = "test" unless ENV["RAILS_ENV"] == "test"
        env["PARALLEL_WORKERS"] = "1"
        env
      end

      def spec_files
        (Dir.glob("test/**/*_test.rb") + Dir.glob("test/**/*_spec.rb"))
          .reject { |f| f.start_with?("test/system/") }
      end
    end
  end
end
