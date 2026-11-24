# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::BootstrapErrorMessage do
  def build_result(log_path:, stdout: "", status: :runtime_error)
    Henitai::ScenarioExecutionResult.new(status:, stdout:, stderr: "", log_path:)
  end

  def timeout_message(seconds)
    "Configured test suite did not finish within #{seconds} s while generating coverage; " \
      "raise mutation.suite_timeout to allow more time"
  end

  it "points at the log" do
    Dir.mktmpdir do |dir|
      log_path = File.join(dir, "suite.log")
      File.write(log_path, "boot\nfailure one\nfailure two\n")

      message = described_class.build(build_result(log_path:))

      expect(message).to start_with("#{described_class::GENERIC} (see #{log_path})")
    end
  end

  it "includes the last lines of the log" do
    Dir.mktmpdir do |dir|
      log_path = File.join(dir, "suite.log")
      File.write(log_path, "boot\nfailure one\nfailure two\n")

      message = described_class.build(build_result(log_path:))

      expect(message).to include("failure one", "failure two")
    end
  end

  it "falls back to the generic message when the log is empty" do
    Dir.mktmpdir do |dir|
      log_path = File.join(dir, "missing.log")

      message = described_class.build(build_result(log_path:, stdout: "  "))

      expect(message).to start_with("#{described_class::GENERIC} (see #{log_path})")
    end
  end

  it "explains a timed-out baseline without calling it a failure" do
    message = described_class.build(build_result(log_path: "/dev/null", status: :timeout), timeout: 900.0)

    expect(message).to start_with(timeout_message(900))
  end

  it "names no number when the limit is unknown" do
    message = described_class.build(build_result(log_path: "/dev/null", status: :timeout))

    expect(message).to start_with(
      "Configured test suite did not finish within the time limit while generating coverage; " \
      "raise mutation.suite_timeout to allow more time"
    )
  end

  it "keeps the fractional part of a non-integer timeout" do
    message = described_class.build(build_result(log_path: "/dev/null", status: :timeout), timeout: 12.5)

    expect(message).to start_with(timeout_message(12.5))
  end

  it "keeps the log path and tail for a timed-out baseline" do
    Dir.mktmpdir do |dir|
      log_path = File.join(dir, "suite.log")
      File.write(log_path, "boot\nslow test\n")

      message = described_class.build(build_result(log_path:, status: :timeout), timeout: 900.0)

      expect(message).to include("(see #{log_path})", "slow test")
    end
  end

  it "returns the generic message for results without a log" do
    expect(described_class.build(Object.new)).to eq(described_class::GENERIC)
  end
end
