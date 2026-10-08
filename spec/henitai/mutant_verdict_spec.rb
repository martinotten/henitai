# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::MutantVerdict do
  def exited(code)
    Struct.new(:exitstatus, :signaled?, :termsig).new(code, false, nil)
  end

  def signaled(signal)
    Struct.new(:exitstatus, :signaled?, :termsig).new(nil, true, Signal.list.fetch(signal))
  end

  def verdict(wait_result, report, stdout: "", stderr: "")
    described_class.new(wait_result:, report:, stdout:, stderr:).to_a
  end

  def tests_finished(exit_code) = { "outcome" => "tests_finished", "exit_code" => exit_code }

  it "classifies a deadline breach as a timeout" do
    expect(verdict(:timeout, nil)).to eq([:timeout, nil])
  end

  it "classifies a passing test run as survived" do
    expect(verdict(exited(0), tests_finished(0))).to eq([:survived, nil])
  end

  it "classifies a failing test run as killed" do
    expect(verdict(exited(1), tests_finished(1))).to eq([:killed, nil])
  end

  it "takes the test verdict from the report rather than the process exit status" do
    expect(verdict(exited(1), tests_finished(0))).to eq([:survived, nil])
  end

  it "classifies a failed activation as a compile error with its reason" do
    report = { "outcome" => "activation_failed", "reason" => "NameError: uninitialized constant Shop::Base" }

    expect(verdict(exited(2), report))
      .to eq([:compile_error, "activation failed: NameError: uninitialized constant Shop::Base"])
  end

  it "classifies a SystemExit during the test run as a runtime error" do
    report = { "outcome" => "system_exit", "status" => 0 }

    expect(verdict(exited(1), report))
      .to eq([:runtime_error, "the test run ended early with SystemExit (status 0)"])
  end

  it "classifies a child killed by a signal as a runtime error" do
    expect(verdict(signaled("KILL"), nil)).to eq([:runtime_error, "child terminated by signal SIGKILL"])
  end

  it "classifies a signal after a finished test run as a runtime error" do
    expect(verdict(signaled("SEGV"), tests_finished(1))).to eq([:runtime_error, "child terminated by signal SIGSEGV"])
  end

  it "classifies a child that exits without a report as a runtime error" do
    expect(verdict(exited(1), nil))
      .to eq([:runtime_error, "child exited with status 1 without reporting a result"])
  end

  it "classifies a run that found no examples as a compile error" do
    expect(verdict(exited(1), tests_finished(1), stdout: "No examples found.\n"))
      .to eq([:compile_error, "no examples ran"])
  end

  it "classifies a run of zero examples as a compile error" do
    expect(verdict(exited(1), tests_finished(1), stdout: "0 examples, 0 failures\n"))
      .to eq([:compile_error, "no examples ran"])
  end

  it "keeps a kill when examples ran and an error occurred outside of them" do
    stdout = "10 examples, 0 failures, 1 error occurred outside of examples\n"

    expect(verdict(exited(1), tests_finished(1), stdout:)).to eq([:killed, nil])
  end

  it "classifies an unknown report outcome as a runtime error" do
    expect(verdict(exited(0), { "outcome" => "bogus" }))
      .to eq([:runtime_error, "child reported an unknown outcome: bogus"])
  end
end
