# frozen_string_literal: true

require "fileutils"
require "stringio"
require_relative "integration/rspec_process_runner"

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
          original_stdout: stdout_stream.dup,
          original_stderr: stderr_stream.dup,
          stdout_file: File.new(log_paths[:stdout_path], "w"),
          stderr_file: File.new(log_paths[:stderr_path], "w")
        }
      end

      def sync_child_output_files(output_files)
        output_files[:stdout_file].sync = true
        output_files[:stderr_file].sync = true
      end

      def redirect_child_output(output_files)
        reopen_child_output_stream(stdout_stream, output_files[:stdout_file])
        reopen_child_output_stream(stderr_stream, output_files[:stderr_file])
        $stdout = stdout_stream
        $stderr = stderr_stream
      end

      def restore_child_output(output_files)
        reopen_child_output_stream(stdout_stream, output_files[:original_stdout])
        reopen_child_output_stream(stderr_stream, output_files[:original_stderr])
        $stdout = stdout_stream
        $stderr = stderr_stream
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

      def stdout_stream
        @stdout_stream ||= IO.for_fd(1)
      end

      def stderr_stream
        @stderr_stream ||= IO.for_fd(2)
      end
    end

    # Shared debug helpers for child-run diagnostics.
    # Debug helpers are intentionally grouped here so the child-run diagnostics
    # stay isolated from the main integration flow.
    # rubocop:disable Metrics/ModuleLength
    module ChildDebugSupport
      private

      def run_rspec_runner(test_files)
        debug_child_puts("[henitai-debug-child] build_rspec_runner_start")
        runner = build_rspec_runner
        debug_child_puts("[henitai-debug-child] build_rspec_runner_return")
        debug_child_puts("[henitai-debug-child] configure_rspec_runner_start")
        configure_rspec_runner(runner)
        debug_child_puts("[henitai-debug-child] configure_rspec_runner_return")
        load_rspec_spec_files(test_files)
        run_rspec_specs(runner)
      rescue SystemExit => e
        debug_child_puts("[henitai-debug-child] runner_run_system_exit status=#{e.status.inspect}")
        raise
      ensure
        debug_child_puts("[henitai-debug-child] runner_run_ensure")
      end

      def build_rspec_runner
        # @type var empty_args: Array[String]
        empty_args = []
        configuration_options = ::RSpec::Core.const_get(:ConfigurationOptions).new(empty_args)
        ::RSpec::Core::Runner.__send__(:new, configuration_options)
      end

      def configure_rspec_runner(runner)
        debug_child_puts("[henitai-debug-child] trap_interrupt_start")
        ::RSpec::Core::Runner.__send__(:trap_interrupt)
        debug_child_puts("[henitai-debug-child] trap_interrupt_return")
        debug_child_puts("[henitai-debug-child] runner_configure_start")
        runner.send(:configure, $stderr, $stdout)
        debug_child_puts("[henitai-debug-child] runner_configure_return")
      end

      def load_rspec_spec_files(test_files)
        debug_child_puts("[henitai-debug-child] load_spec_files_start")
        ::RSpec.__send__(:configuration).files_to_run = test_files.map do |file|
          File.expand_path(file)
        end
        ::RSpec.__send__(:configuration).load_spec_files
        debug_child_example_count("after_load")
        debug_child_puts("[henitai-debug-child] load_spec_files_return")
      end

      def run_rspec_specs(runner)
        debug_child_puts("[henitai-debug-child] run_specs_start")
        result = runner.send(:run_specs, ::RSpec.__send__(:world).ordered_example_groups)
        debug_child_puts("[henitai-debug-child] run_specs_return result=#{result.inspect}")
        result
      end

      def debug_child? = ENV["HENITAI_DEBUG_CHILD"] == "1"

      def debug_child_puts(message)
        $stdout.puts(message)
        $stdout.flush
      end

      def debug_child_rspec_trace(test_files:, rspec_options:, rspec_argv:)
        return unless debug_child?

        files_exist = test_files.map { |f| [f, File.exist?(f)] }.inspect
        loaded_features = loaded_feature_map(test_files).inspect # steep:ignore Ruby::NoMethod

        debug_child_puts(
          "[henitai-debug-child] cwd=#{Dir.pwd}\n" \
          "[henitai-debug-child] files_exist=#{files_exist}\n" \
          "[henitai-debug-child] loaded_features_check=#{loaded_features}\n" \
          "[henitai-debug-child] test_files=#{test_files.inspect}\n" \
          "[henitai-debug-child] rspec_options=#{rspec_options.inspect}\n" \
          "[henitai-debug-child] rspec_argv=#{rspec_argv.inspect}"
        )
      end

      def debug_child_rspec_exit(status)
        return unless debug_child?

        debug_child_puts("[henitai-debug-child] RSpec result=#{status.inspect}")
      end

      def suppress_simplecov!
        CoverageRuntimeSuppressors.suppress_simplecov!
      end

      def suppress_coverage!
        CoverageRuntimeSuppressors.suppress_coverage!
      end

      def debug_child_example_count(stage) # steep:ignore Ruby::UndeclaredMethodDefinition
        return unless debug_child?

        count = rspec_world_example_count
        debug_child_puts(
          "[henitai-debug-child] rspec_world_example_count_#{stage}=#{count.inspect}"
        )
      end

      def debug_child_activation_start(mutant_id)
        return unless debug_child?

        debug_child_puts("[henitai-debug-child] activate_start mutant=#{mutant_id}")
      end

      def debug_child_activation_end(activation_result, test_files:)
        return unless debug_child?

        debug_child_puts(
          "[henitai-debug-child] activate_end result=#{activation_result.inspect}\n" \
          "[henitai-debug-child] run_tests_start test_files=#{test_files.inspect}"
        )
      end

      def debug_child_mutant_meta(mutant)
        stable_id = mutant.respond_to?(:stable_id) ? mutant.stable_id : nil
        operator = mutant.respond_to?(:operator) ? mutant.operator : nil
        has_subject_expression =
          mutant.respond_to?(:subject) && mutant.subject.respond_to?(:expression)
        subject_expression = has_subject_expression ? mutant.subject.expression : nil
        location = mutant.respond_to?(:location) ? mutant.location.inspect : nil

        debug_child_puts(
          "[henitai-debug-child] mutant_meta stableId=#{stable_id}\n" \
          "[henitai-debug-child] mutant_meta operator=#{operator}\n" \
          "[henitai-debug-child] mutant_meta subject=#{subject_expression}\n" \
          "[henitai-debug-child] mutant_meta location=#{location}\n"
        )
      end

      def debug_child_activation_check
        location = begin
          Henitai::Runner.instance_method(:resolve_subjects).source_location&.join(":")
        rescue StandardError
          nil
        end

        debug_child_puts(
          "[henitai-debug-child] activation_check resolve_subjects_location=#{location}\n"
        )
      end

      def loaded_feature_map(test_files) = test_files.map { |file| [file, loaded_feature?(file)] } # steep:ignore Ruby::UndeclaredMethodDefinition

      def loaded_feature?(file) # steep:ignore Ruby::UndeclaredMethodDefinition
        expanded = File.expand_path(file)
        candidates = [expanded, "#{expanded}.rb", file, "#{file}.rb"].uniq
        $LOADED_FEATURES.any? do |feature|
          normalized = begin
            File.expand_path(feature)
          rescue StandardError
            feature
          end
          candidates.include?(feature) || candidates.include?(normalized)
        end
      end

      def rspec_world_example_count # steep:ignore Ruby::UndeclaredMethodDefinition
        world = ::RSpec.__send__(:world)
        world.example_count
      rescue StandardError
        nil
      end

      def debug_child_timeout_dump(pid)
        return unless debug_child?

        debug_child_puts("[henitai-debug-child] timeout_signal_sent pid=#{pid}")
        Process.kill(:USR1, pid)
        pause(0.2)
      rescue Errno::ESRCH
        nil
      end

      def install_debug_timeout_trap
        Signal.trap("USR1") { debug_child_thread_dump("timeout") }
      end

      def debug_child_thread_dump(reason)
        return unless debug_child?

        debug_child_puts("[henitai-debug-child] thread_dump reason=#{reason}")
        Thread.list.each_with_index do |thread, index|
          debug_child_puts(
            "[henitai-debug-child] thread index=#{index} id=#{thread.object_id} " \
            "status=#{thread.status.inspect}"
          )
          Array(thread.backtrace).each do |line|
            debug_child_puts("[henitai-debug-child]   #{line}")
          end
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength

    # Integration adapter for RSpec.
    #
    # This class exists as the stable public entry point for the RSpec
    # integration, even though the concrete behavior is not implemented yet.
    # @param name [String] integration name, e.g. "rspec"
    # @return [Class] integration class
    def self.for(name)
      const_get(name.capitalize)
    rescue NameError
      available = constants.filter_map do |constant_name|
        integration = const_get(constant_name)
        constant_name.to_s.downcase if integration.is_a?(Class) && integration < Base
      end.sort.join(", ")

      raise ArgumentError, "Unknown integration: #{name}. Available: #{available}"
    end

    # Base class for all integrations.
    class Base
      include ChildDebugSupport

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
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

        loop do
          wait_result = Process.wait(pid, Process::WNOHANG)
          return Process.last_status if wait_result

          if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            final_wait_result = Process.wait(pid, Process::WNOHANG)
            return Process.last_status if final_wait_result

            return handle_timeout(pid)
          end

          pause(0.01)
        end
      end

      def reap_child(pid)
        Process.wait(pid)
      rescue Errno::ECHILD, Errno::ESRCH
        nil
      end

      def cleanup_process_group(pid)
        Process.kill(:SIGTERM, -pid)
        pause(2.0)
        Process.kill(:SIGKILL, -pid)
      rescue Errno::EPERM
        cleanup_child_process(pid)
      rescue Errno::ESRCH
        nil
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
        Process.kill(:SIGTERM, pid)
        pause(2.0)
        Process.kill(:SIGKILL, pid)
      rescue Errno::EPERM, Errno::ESRCH
        nil
      end

      def subprocess_env
        { "PARALLEL_WORKERS" => "1" }
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

      def spawn_mutant(mutant:, test_files:)
        log_paths = scenario_log_paths(mutant_log_name(mutant))
        RspecProcessRunner.new.spawn_mutant(self, mutant:, test_files:, log_paths:)
      end

      def run_mutant(mutant:, test_files:, timeout:)
        RspecProcessRunner.new.run_mutant(self, mutant:, test_files:, timeout:)
      end

      def per_test_coverage_supported?
        true
      end

      def run_suite(test_files, timeout: DEFAULT_SUITE_TIMEOUT)
        RspecProcessRunner.new.run_suite(self, test_files, timeout:)
      end

      def suite_command(test_files)
        [
          "bundle", "exec", "ruby",
          "-r", "henitai/rspec_coverage_formatter",
          "-e", rspec_suite_runner_script,
          *test_files
        ]
      end

      def rspec_suite_runner_script
        <<~RUBY
          require "rspec/core"

          test_files = ARGV.map { |file| File.expand_path(file) }
          config = RSpec.configuration
          options = RSpec::Core::ConfigurationOptions.new(
            ["--format", "progress", "--format", "Henitai::CoverageFormatter"]
          )
          runner = RSpec::Core::Runner.send(:new, options)

          RSpec::Core::Runner.send(:trap_interrupt)
          runner.send(:configure, $stderr, $stdout)
          config.files_to_run = test_files
          config.load_spec_files

          status = runner.send(:run_specs, RSpec.world.ordered_example_groups)
          exit(status.is_a?(Integer) ? status : (status == true ? 0 : 1))
        RUBY
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
        stdout = read_log_file(log_paths[:stdout_path])
        stderr = read_log_file(log_paths[:stderr_path])
        write_combined_log(log_paths[:log_path], stdout, stderr)

        ScenarioExecutionResult.build(
          wait_result:,
          stdout:,
          stderr:,
          log_path: log_paths[:log_path]
        )
      end

      def spec_files
        paths = Dir.glob("spec/**/*_spec.rb")
        paths - excluded_spec_files
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

      def excluded_spec_files
        rspec_exclude_patterns.flat_map { |pattern| Dir.glob(pattern) }.uniq
      end

      def rspec_exclude_patterns
        rspec_config_lines.filter_map do |line|
          line[/\A--exclude-pattern\s+(.+)\z/, 1]
        end
      end

      def rspec_config_lines
        return [] unless File.exist?(rspec_config_path)

        File.readlines(rspec_config_path, chomp: true).map(&:strip)
      end

      def rspec_config_path
        ".rspec"
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

      def spawn_suite_process(test_files, log_paths)
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

      def run_in_child(mutant:, test_files:, log_paths:)
        Thread.report_on_exception = false
        with_subprocess_env do
          suppress_simplecov!
          suppress_coverage!
          install_debug_timeout_trap if debug_child?
          with_non_interactive_stdin do
            run_child_activation_and_tests(mutant:, test_files:, log_paths:)
          end
        end
      end

      def mutant_log_name(mutant)
        "mutant-#{mutant.id}"
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
    end

    # Stores the child-process log helpers shared by the integration specs.
    class ScenarioLogSupport
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
    end

    # Prepended onto SimpleCov's singleton class to turn start into a no-op
    # during mutant child runs. Using prepend avoids "method redefined" warnings.
    module SimpleCovStartSuppressor
      def start(*_args) = nil
    end

    # Suppresses expensive and irrelevant coverage startup/teardown during
    # mutant child runs. Coverage artifacts are only required during the
    # dedicated bootstrap phase.
    module CoverageRuntimeSuppressors
      def self.suppress_simplecov!
        require "simplecov"
        sc = Object.const_get(:SimpleCov) # steep:ignore Ruby::UnknownConstant
        sc.external_at_exit = true if sc.respond_to?(:external_at_exit=)
        return if sc.singleton_class.ancestors.include?(SimpleCovStartSuppressor)

        sc.singleton_class.prepend(SimpleCovStartSuppressor)
      rescue LoadError, NameError
        nil
      end

      def self.suppress_coverage!
        require "coverage"
        cov = Object.const_get(:Coverage) # steep:ignore Ruby::UnknownConstant
        return if cov.singleton_class.ancestors.include?(CoverageStartSuppressor)

        cov.singleton_class.prepend(CoverageStartSuppressor)
      rescue LoadError, NameError
        nil
      end
    end

    # Prepended onto the coverage gem's Coverage singleton to turn start
    # into a no-op during mutant child runs.
    module CoverageStartSuppressor
      def start(*_args) = nil
    end

    # Minitest integration adapter.
    #
    # Coverage formatter injection remains implemented in the RSpec child
    # runner. Minitest shares selection and execution semantics, but per-test
    # coverage collection is not yet wired into this path.
    class Minitest < Rspec
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

      def suppress_simplecov!
        require "simplecov"
        sc = Object.const_get(:SimpleCov) # steep:ignore Ruby::UnknownConstant
        return if sc.singleton_class.ancestors.include?(SimpleCovStartSuppressor)

        sc.singleton_class.prepend(SimpleCovStartSuppressor)
      rescue LoadError, NameError
        nil
      end

      def suppress_coverage!
        require "coverage"
        cov = Object.const_get(:Coverage) # steep:ignore Ruby::UnknownConstant
        return if cov.singleton_class.ancestors.include?(CoverageStartSuppressor)

        cov.singleton_class.prepend(CoverageStartSuppressor)
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
