# frozen_string_literal: true

module Henitai
  # Captures the result of one baseline or mutant test run.
  class ScenarioExecutionResult
    attr_reader :status, :status_reason, :stdout, :stderr, :exit_status, :log_path, :killing_tests, :hanging_test

    def self.build(wait_result:, stdout:, stderr:, log_path:)
      new(
        status: status_for(wait_result, stdout:, stderr:),
        stdout: stdout,
        stderr: stderr,
        log_path: log_path,
        exit_status: exit_status_for(wait_result)
      )
    end

    # Copies the reason behind a harness status onto the mutant the result was
    # produced for. Tolerates results and mutants that carry no reason.
    def self.copy_reason(result, mutant)
      return unless result.respond_to?(:status_reason) && mutant.respond_to?(:status_reason=)

      mutant.status_reason = result.status_reason
    end

    # The verdict of a child that could not be spawned at all.
    def self.spawn_failure(error)
      new(status: :compile_error, stdout: "", stderr: "spawn failed: #{error.message}", log_path: "/dev/null")
    end

    # Classifies a mutant run from the child's report (see MutantVerdict).
    # +running_test+ is the test file the child was executing when it was
    # killed; it is kept only for a timeout (see #hanging_test).
    # rubocop:disable Metrics/ParameterLists -- one keyword per captured field
    def self.build_for_mutant(wait_result:, report:, stdout:, stderr:, log_path:, running_test: nil)
      # rubocop:enable Metrics/ParameterLists
      verdict = MutantVerdict.new(wait_result:, report:, stdout:, stderr:)
      status, status_reason = verdict.to_a
      new(status:, status_reason:, stdout:, stderr:, log_path:, exit_status: exit_status_for(wait_result),
          killing_tests: verdict.killing_tests, hanging_test: hanging_test_for(status, running_test))
    end

    # rubocop:disable Metrics/ParameterLists -- one keyword per captured field
    def initialize(status:, stdout:, stderr:, log_path:, exit_status: nil, status_reason: nil, killing_tests: [],
                   hanging_test: nil)
      # rubocop:enable Metrics/ParameterLists
      @status = status
      @status_reason = status_reason
      @stdout = stdout.to_s
      @stderr = stderr.to_s
      @log_path = log_path
      @exit_status = exit_status
      @killing_tests = killing_tests
      @hanging_test = hanging_test
    end

    # The same run under a different verdict, e.g. a detection a failing
    # control reclassified (ADR-14). Output and exit data are kept.
    def reclassified(status:, status_reason:)
      self.class.new(status:, status_reason:, stdout:, stderr:, log_path:, exit_status:, killing_tests:,
                     hanging_test:)
    end

    # Frees the captured child output once it has been consumed (e.g. by the
    # progress reporter). The scheduler retains one result per mutant for the
    # whole run; without this a runaway mutant's multi-hundred-MB output would
    # stay resident until the run ends. Status/log_path/exit_status are kept so
    # the result stays usable for scoring and log lookups.
    def release_output!
      @stdout = ""
      @stderr = ""
      @log_text = nil
      self
    end

    def survived?
      status == :survived
    end

    def killed?
      status == :killed
    end

    def timeout?
      status == :timeout
    end

    def ==(other)
      return status == other.status if other.respond_to?(:status)
      return status == other if other.is_a?(Symbol)

      super
    end

    def log_text
      @log_text ||= if File.exist?(log_path)
                      File.read(log_path)
                    else
                      combined_output
                    end
    end

    def combined_output
      [
        (stdout.empty? ? nil : stream_section("stdout", stdout)),
        (stderr.empty? ? nil : stream_section("stderr", stderr))
      ].compact.join("\n")
    end

    def tail(lines = 12)
      log_text.lines.last(lines).join
    end

    def should_show_logs?(all_logs: nil)
      all_logs || timeout? || status == :compile_error
    end

    def failure_tail(all_logs: nil, lines: 12)
      return combined_output if all_logs
      return "" unless should_show_logs?(all_logs:)

      tail(lines)
    end

    private

    class << self
      private

      # The test file a timed-out child was running; nil for any other verdict.
      def hanging_test_for(status, running_test)
        status == :timeout ? running_test : nil
      end

      def status_for(wait_result, stdout:, stderr:)
        return :timeout if wait_result == :timeout
        return :compile_error if no_examples_found?(stdout, stderr)
        return :compile_error if zero_examples_failure?(wait_result, stdout, stderr)
        return :compile_error if exit_status_for(wait_result) == 2
        return :survived if wait_result.respond_to?(:success?) && wait_result.success?

        :killed
      end

      def exit_status_for(wait_result)
        return nil if wait_result == :timeout
        return nil unless wait_result.respond_to?(:exitstatus)

        wait_result.exitstatus
      end

      def no_examples_found?(stdout, stderr)
        output = [stdout.to_s, stderr.to_s].join("\n")
        return false unless ExampleSummary::NO_EXAMPLES_FOUND.match?(output)

        last_summary = output.scan(ExampleSummary::SUMMARY).last
        last_summary.nil? || last_summary == ["0"]
      end

      def zero_examples_failure?(wait_result, stdout, stderr)
        return false unless exit_status_for(wait_result) == 1

        ExampleSummary.none_ran?([stdout.to_s, stderr.to_s].join("\n"))
      end
    end

    def stream_section(name, content)
      "#{name}:\n#{content}"
    end
  end
end
