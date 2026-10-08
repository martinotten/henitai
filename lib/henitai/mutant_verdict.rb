# frozen_string_literal: true

module Henitai
  # Classifies one mutant run from the child's own report and the way the
  # child process ended.
  #
  # The child reports what it got to: a failed activation, a finished test run
  # with the exit code the tests returned, or a SystemExit raised while the
  # tests ran. Only a finished test run yields a test verdict (Killed or
  # Survived); everything else is a harness or runtime status that stays out of
  # the detected count. In particular a child that died without a report, or
  # was killed by a signal, is a RuntimeError, never a kill.
  class MutantVerdict
    NO_EXAMPLES = /No examples found\.|\b0 examples, 0 failures/

    def initialize(wait_result:, report:, stdout:, stderr:)
      @wait_result = wait_result
      @report = report
      @output = "#{stdout}\n#{stderr}"
    end

    # @return [Array(Symbol, String|nil)] status and reason
    def to_a
      return [:timeout, nil] if @wait_result == :timeout
      return [:runtime_error, "child terminated by signal #{signal_name}"] if signaled?
      return [:runtime_error, "child exited with status #{exit_status} without reporting a result"] unless @report

      reported_verdict
    end

    private

    def reported_verdict
      case @report["outcome"]
      when "activation_failed" then [:compile_error, "activation failed: #{@report['reason']}"]
      when "system_exit"
        [:runtime_error, "the test run ended early with SystemExit (status #{@report['status']})"]
      when "tests_finished" then test_verdict
      else [:runtime_error, "child reported an unknown outcome: #{@report['outcome']}"]
      end
    end

    def test_verdict
      return [:compile_error, "no examples ran"] if NO_EXAMPLES.match?(@output)

      @report["exit_code"].to_i.zero? ? [:survived, nil] : [:killed, nil]
    end

    def signaled?
      @wait_result.respond_to?(:signaled?) && @wait_result.signaled?
    end

    def signal_name
      "SIG#{Signal.signame(@wait_result.termsig)}"
    end

    def exit_status
      @wait_result.respond_to?(:exitstatus) ? @wait_result.exitstatus : "unknown"
    end
  end
end
