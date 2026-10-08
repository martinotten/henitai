# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ControlRun do
  let(:subject_a) { Henitai::Subject.new(namespace: "Sample", method_name: "a") }
  let(:subject_b) { Henitai::Subject.new(namespace: "Sample", method_name: "b") }

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

  def integration_returning(status, reason = nil)
    integration = instance_double(Henitai::Integration::Rspec)
    allow(integration).to receive(:run_mutant).and_return(control_result(status, reason))
    integration
  end

  def verify(mutants, integration)
    described_class.new(integration:, timeout_for: ->(_files) { 5.0 }).verify(mutants)
  end

  it "reclassifies the detected verdicts of a subject whose control run fails" do
    mutants = [mutant(subject_a, :killed), mutant(subject_a, :timeout), mutant(subject_a, :survived)]

    verify(mutants, integration_returning(:killed))

    expect(mutants.map(&:status)).to eq(%i[compile_error compile_error survived])
  end

  it "explains the reclassification" do
    killed = mutant(subject_a, :killed)

    verify([killed], integration_returning(:runtime_error, "child terminated by signal SIGKILL"))

    expect(killed.status_reason).to eq(
      "control run failed: the unmutated method fails its tests when injected " \
      "(runtime_error: child terminated by signal SIGKILL)"
    )
  end

  it "keeps the verdicts when the control run survives" do
    killed = mutant(subject_a, :killed)

    verify([killed], integration_returning(:survived))

    expect(killed.status).to eq(:killed)
  end

  it "runs one control per subject and test-file set" do
    integration = integration_returning(:survived)
    mutants = [mutant(subject_a, :killed), mutant(subject_a, :killed), mutant(subject_b, :killed),
               mutant(subject_b, :killed, covered_by: ["spec/other_spec.rb"])]

    verify(mutants, integration)

    expect(integration).to have_received(:run_mutant).exactly(3).times
  end

  it "skips subjects without detected verdicts and verdicts reused from history" do
    integration = integration_returning(:killed)
    cached = mutant(subject_b, :killed).tap { |built| built.from_cache = true }

    verify([mutant(subject_a, :survived), cached], integration)

    expect(integration).not_to have_received(:run_mutant)
  end

  it "runs the control with the unmutated node, the same test files and their timeout" do
    integration = integration_returning(:survived)
    killed = mutant(subject_a, :killed)

    calls = []
    allow(integration).to receive(:run_mutant) do |mutant:, test_files:, timeout:|
      calls << [mutant.mutated_node.equal?(mutant.original_node), test_files, timeout]
      control_result(:survived)
    end

    verify([killed], integration)

    expect(calls).to eq([[true, ["spec/sample_spec.rb"], 5.0]])
  end

  it "reports how many subjects it verified and how many failed" do
    integration = instance_double(Henitai::Integration::Rspec)
    allow(integration).to receive(:run_mutant).and_return(control_result(:survived), control_result(:killed))

    stats = verify([mutant(subject_a, :killed), mutant(subject_b, :killed)], integration)

    expect(stats).to eq(verified: 2, failed: 1, reclassified: 1)
  end
end
