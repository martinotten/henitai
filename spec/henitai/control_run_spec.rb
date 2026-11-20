# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ControlRun do
  let(:subject_a) { Henitai::Subject.new(namespace: "Sample", method_name: "a") }
  let(:subject_b) { Henitai::Subject.new(namespace: "Sample", method_name: "b") }
  let(:control_run) { described_class.new }

  def mutant(subject, status, covered_by: ["spec/sample_spec.rb"])
    node = Henitai::SourceParser.parse("1 + 2")
    Henitai::Mutant.new(
      subject:, operator: "ArithmeticOperator", nodes: { original: node, mutated: node.updated(nil, nil) },
      description: "replaced + with -", location: { file: "lib/sample.rb", start_line: 1, end_line: 1 }
    ).tap do |built|
      built.status = status
      built.covered_by = covered_by
    end
  end

  def control_result(status, reason = nil)
    Henitai::ScenarioExecutionResult.new(status:, status_reason: reason, stdout: "", stderr: "", log_path: "/dev/null")
  end

  it "reclassifies detections as CompileError and explains why", :aggregate_failures do
    killed = mutant(subject_a, :killed)
    timeout = mutant(subject_a, :timeout)

    failed = control_result(:runtime_error, "child terminated by signal SIGKILL")
    count = control_run.reclassify([killed, timeout], failed)

    expect(count).to eq(2)
    expect([killed.status, timeout.status]).to eq(%i[compile_error compile_error])
    expect(killed.status_reason).to eq(
      "control run failed: the unmutated method fails its tests when injected " \
      "(runtime_error: child terminated by signal SIGKILL)"
    )
  end

  it "passes only a surviving control" do
    expect(%i[survived killed timeout].map { |status| control_run.passed?(control_result(status)) })
      .to eq([true, false, false])
  end

  it "controls detections of this run that carry their original node" do
    expect(%i[killed timeout runtime_error].map { |status| control_run.controllable?(mutant(subject_a, status)) })
      .to all(be(true))
  end

  it "does not control survivors, reused verdicts or recipe stubs" do
    cached = mutant(subject_a, :killed).tap { |built| built.from_cache = true }
    stub = Struct.new(:status, :from_cache?, :original_node).new(:killed, false, nil)

    expect([mutant(subject_a, :survived), cached, stub].map { |entry| control_run.controllable?(entry) })
      .to eq([false, false, false])
  end

  it "groups detections by subject and sorted test files" do
    first = mutant(subject_a, :killed, covered_by: %w[b_spec.rb a_spec.rb])
    second = mutant(subject_a, :timeout, covered_by: %w[a_spec.rb b_spec.rb])
    other = mutant(subject_b, :killed, covered_by: %w[a_spec.rb b_spec.rb])

    expect([control_run.group_key(first) == control_run.group_key(second),
            control_run.group_key(first) == control_run.group_key(other)]).to eq([true, false])
  end

  it "builds the control from the unmutated node, as a Control mutant at the same place", :aggregate_failures do
    detected = mutant(subject_a, :killed)

    control = control_run.control_mutant(detected)

    expect(control.mutated_node).to equal(detected.original_node)
    expect([control.operator, control.subject, control.location]).to eq(["Control", subject_a, detected.location])
  end

  it "runs the control against the detection's test files, sorted" do
    expect(control_run.test_files(mutant(subject_a, :killed, covered_by: %w[b_spec.rb a_spec.rb])))
      .to eq(%w[a_spec.rb b_spec.rb])
  end
end
