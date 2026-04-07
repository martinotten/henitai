# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::ScenarioExecutionResult do
  def build_result(status, stdout: "", stderr: "", log_path: "/tmp/nonexistent-henitai-test.log")
    described_class.new(status:, stdout:, stderr:, log_path:)
  end

  it "equals another result with the same status" do
    a = build_result(:survived)
    b = build_result(:survived)
    expect(a).to eq(b)
  end

  it "does not equal another result with a different status" do
    expect(build_result(:survived)).not_to eq(build_result(:killed))
  end

  it "equals the matching status symbol" do
    expect(build_result(:survived)).to eq(:survived)
  end

  it "does not equal a non-matching status symbol" do
    expect(build_result(:survived)).not_to eq(:killed)
  end

  it "reads log_text from the log file when it exists" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "run.log")
      File.write(path, "log content from file")
      r = described_class.new(status: :killed, stdout: "fallback", stderr: "", log_path: path)
      expect(r.log_text).to eq("log content from file")
    end
  end

  it "falls back to combined_output when the log file does not exist" do
    r = described_class.new(
      status: :killed,
      stdout: "stdout content",
      stderr: "",
      log_path: "/tmp/does-not-exist-henitai-#{Process.pid}.log"
    )
    expect(r.log_text).to include("stdout content")
  end

  it "does not show logs by default for non-timeout results" do
    expect(build_result(:survived).should_show_logs?).to be(false)
  end

  it "shows logs without arguments when status is timeout" do
    expect(build_result(:timeout).should_show_logs?).to be(true)
  end

  it "shows logs when all_logs is enabled" do
    expect(build_result(:survived).should_show_logs?(all_logs: true)).to be(true)
  end

  it "combines stdout and stderr with labeled sections" do
    result = build_result(:killed, stdout: "stdout content", stderr: "stderr content")

    expect(result.combined_output).to eq(
      "stdout:\nstdout content\nstderr:\nstderr content"
    )
  end

  it "returns the combined output when all_logs is enabled" do
    result = build_result(:killed, stdout: "stdout content", stderr: "stderr content")

    expect(result.failure_tail(all_logs: true)).to eq(result.combined_output)
  end

  it "returns the tail for timeout results when all_logs is omitted" do
    result = build_result(
      :timeout,
      stdout: "stdout line 1\nstdout line 2",
      stderr: ""
    )

    expect(result.failure_tail).to eq(result.tail)
  end
end
