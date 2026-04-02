# frozen_string_literal: true

module Henitai
  # Captures the result of one baseline or mutant test run.
  class ScenarioExecutionResult
    attr_reader :status, :stdout, :stderr, :exit_status, :log_path

    def initialize(status:, stdout:, stderr:, log_path:, exit_status: nil)
      @status = status
      @stdout = stdout.to_s
      @stderr = stderr.to_s
      @log_path = log_path
      @exit_status = exit_status
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

    def should_show_logs?(all_logs: false)
      all_logs || timeout?
    end

    def failure_tail(all_logs: false, lines: 12)
      return combined_output if all_logs
      return "" unless should_show_logs?(all_logs:)

      tail(lines)
    end

    private

    def stream_section(name, content)
      "#{name}:\n#{content}"
    end
  end
end
