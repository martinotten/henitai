# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::ScenarioExecutionResult do
  def build_result(status, stdout: "", stderr: "", log_path: "/tmp/nonexistent-henitai-test.log")
    described_class.new(status:, stdout:, stderr:, log_path:)
  end

  def build_wait_result(success:, exitstatus:)
    Struct.new(:success?, :exitstatus).new(success, exitstatus)
  end

  def build_exitstatus_only_result(exitstatus)
    Struct.new(:exitstatus).new(exitstatus)
  end

  def build_comparable_status(target)
    Struct.new(:target) do
      def ==(other)
        other == target
      end

      def >=(_other)
        false
      end
    end.new(target)
  end

  def build_timeout_like_wait_result(exitstatus)
    Class.new do
      attr_reader :exitstatus

      def initialize(exitstatus)
        @exitstatus = exitstatus
      end

      def ==(other)
        other == :timeout
      end

      def <=>(_other)
        nil
      end
    end.new(exitstatus)
  end

  def write_log_file(dir, lines)
    path = File.join(dir, "run.log")
    File.write(path, "#{lines.join("\n")}\n")
    path
  end

  it "builds a timeout result from a timeout wait result" do
    result = described_class.build(
      wait_result: :timeout,
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )

    expect(result).to have_attributes(
      status: :timeout,
      exit_status: nil,
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )
  end

  it "builds a survived result from a successful wait result" do
    result = described_class.build(
      wait_result: build_wait_result(success: true, exitstatus: 0),
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )

    expect(result).to have_attributes(
      status: :survived,
      exit_status: 0,
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )
  end

  it "builds a compile error result from an exit status of 2" do
    result = described_class.build(
      wait_result: build_wait_result(success: false, exitstatus: 2),
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )

    expect(result).to have_attributes(
      status: :compile_error,
      exit_status: 2,
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )
  end

  it "builds a compile error result from an exit status of 2.0" do
    result = described_class.build(
      wait_result: build_wait_result(success: false, exitstatus: 2.0),
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )

    expect(result).to have_attributes(
      status: :compile_error,
      exit_status: 2.0,
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )
  end

  it "builds a killed result from a failing wait result" do
    result = described_class.build(
      wait_result: build_wait_result(success: false, exitstatus: 1),
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )

    expect(result).to have_attributes(
      status: :killed,
      exit_status: 1,
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )
  end

  it "builds a killed result when the wait result has no exit status" do
    result = described_class.build(
      wait_result: Object.new,
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )

    expect(result).to have_attributes(
      status: :killed,
      exit_status: nil,
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )
  end

  it "builds a timeout result from a timeout-like wait result with an exit status" do
    result = described_class.build(
      wait_result: build_timeout_like_wait_result(1),
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )

    expect(result).to have_attributes(
      status: :timeout,
      exit_status: nil,
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )
  end

  it "builds a killed result from a non-timeout wait result with exit status 3" do
    result = described_class.build(
      wait_result: build_exitstatus_only_result(3),
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )

    expect(result).to have_attributes(
      status: :killed,
      exit_status: 3,
      stdout: "stdout",
      stderr: "stderr",
      log_path: "/tmp/run.log"
    )
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

  it "does not equal the timeout symbol when the status is killed" do
    expect(build_result(:killed)).not_to eq(:timeout)
  end

  it "equals another object that exposes a matching status" do
    other = Struct.new(:status).new(:survived)

    expect(build_result(:survived) == other).to be(true)
  end

  it "equals another object that exposes a matching non-symbol status" do
    other = Struct.new(:status).new(1)

    expect(build_result(1.0) == other).to be(true)
  end

  it "does not equal a different result status that sorts after the current one" do
    expect(build_result(:killed)).not_to eq(build_result(:timeout))
  end

  it "compares a comparable status object against a timeout symbol" do
    expect(build_result(build_comparable_status(:timeout)).timeout?).to be(true)
  end

  it "compares a comparable status object against a matching status object" do
    other = Struct.new(:status).new(:survived)

    expect(build_result(build_comparable_status(:survived)) == other).to be(true)
  end

  it "compares a comparable status object against a matching symbol" do
    expect(build_result(build_comparable_status(:survived)) == :survived).to be(true)
  end

  it "falls back to Object#== for non-symbol values" do
    expect(build_result("survived") == "survived").to be(false)
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

  it "omits the stdout section when stdout is empty" do
    result = build_result(:killed, stdout: "", stderr: "stderr content")

    expect(result.combined_output).to eq("stderr:\nstderr content")
  end

  it "omits the stderr section when stderr is empty" do
    result = build_result(:killed, stdout: "stdout content", stderr: "")

    expect(result.combined_output).to eq("stdout:\nstdout content")
  end

  it "returns the last requested lines from the log text" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "run.log")
      File.write(path, "line 1\nline 2\nline 3\n")
      result = described_class.new(status: :killed, stdout: "", stderr: "", log_path: path)

      expect(result.tail(2)).to eq("line 2\nline 3\n")
    end
  end

  it "returns the combined output when all_logs is enabled" do
    result = build_result(:killed, stdout: "stdout content", stderr: "stderr content")

    expect(result.failure_tail(all_logs: true)).to eq(result.combined_output)
  end

  it "returns the combined output for all_logs even when a log file exists" do
    Dir.mktmpdir do |dir|
      path = write_log_file(dir, ["line 1", "line 2", "line 3", "line 4"])
      result = described_class.new(
        status: :killed,
        stdout: "stdout content",
        stderr: "stderr content",
        log_path: path
      )

      expect(result.failure_tail(all_logs: true)).to eq(result.combined_output)
    end
  end

  it "returns an empty failure tail for non-timeout results" do
    result = build_result(:survived, stdout: "stdout content", stderr: "stderr content")

    expect(result.failure_tail).to eq("")
  end

  it "returns an empty failure tail for non-timeout results even when a log file exists" do
    Dir.mktmpdir do |dir|
      path = write_log_file(dir, ["line 1", "line 2", "line 3", "line 4"])
      result = described_class.new(
        status: :survived,
        stdout: "stdout content",
        stderr: "stderr content",
        log_path: path
      )

      expect(result.failure_tail).to eq("")
    end
  end

  it "returns the tail for timeout results when all_logs is omitted" do
    result = build_result(
      :timeout,
      stdout: "stdout line 1\nstdout line 2",
      stderr: ""
    )

    expect(result.failure_tail).to eq(result.tail)
  end

  it "returns the log tail for timeout results when all_logs is omitted and a log file exists" do
    Dir.mktmpdir do |dir|
      path = write_log_file(
        dir,
        [
          "line 1",
          "line 2",
          "line 3",
          "line 4",
          "line 5",
          "line 6",
          "line 7",
          "line 8",
          "line 9",
          "line 10",
          "line 11",
          "line 12",
          "line 13"
        ]
      )
      result = described_class.new(
        status: :timeout,
        stdout: "stdout content",
        stderr: "stderr content",
        log_path: path
      )

      expect(result.failure_tail).to eq(
        "line 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\n"
      )
    end
  end
end
