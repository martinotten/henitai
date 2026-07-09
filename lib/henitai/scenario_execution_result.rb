# frozen_string_literal: true

module Henitai
  # Captures the result of one baseline or mutant test run.
  class ScenarioExecutionResult
    attr_reader :status, :stdout, :stderr, :exit_status, :log_path

    def self.build(wait_result:, stdout:, stderr:, log_path:)
      new(
        status: status_for(wait_result, stdout:, stderr:),
        stdout: stdout,
        stderr: stderr,
        log_path: log_path,
        exit_status: exit_status_for(wait_result)
      )
    end

    def initialize(status:, stdout:, stderr:, log_path:, exit_status: nil)
      @status = status
      @stdout = stdout.to_s
      @stderr = stderr.to_s
      @log_path = log_path
      @exit_status = exit_status
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
        stdout.to_s.include?("No examples found.") || stderr.to_s.include?("No examples found.")
      end

      def zero_examples_failure?(wait_result, stdout, stderr)
        return false unless exit_status_for(wait_result) == 1

        output = [stdout.to_s, stderr.to_s].join("\n")
        output.include?("0 examples, 0 failures")
      end
    end

    def stream_section(name, content)
      "#{name}:\n#{content}"
    end
  end
end
