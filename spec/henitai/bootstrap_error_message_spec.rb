# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::BootstrapErrorMessage do
  def build_result(log_path:, stdout: "")
    Henitai::ScenarioExecutionResult.new(status: :runtime_error, stdout:, stderr: "", log_path:)
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

  it "returns the generic message for results without a log" do
    expect(described_class.build(Object.new)).to eq(described_class::GENERIC)
  end
end
