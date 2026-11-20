# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ControlGate do
  let(:subject_a) { Henitai::Subject.new(namespace: "Sample", method_name: "a") }
  let(:subject_b) { Henitai::Subject.new(namespace: "Sample", method_name: "b") }
  let(:delivered) { [] }
  let(:downstream) do
    sink = delivered
    Class.new do
      define_method(:progress) do |mutant, scenario_result: nil|
        sink << [mutant, mutant.status, scenario_result&.status]
      end
    end.new
  end
  let(:launches) { [] }

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

  def result(status, reason = nil)
    Henitai::ScenarioExecutionResult.new(status:, status_reason: reason, stdout: "out", stderr: "",
                                         log_path: "/dev/null")
  end

  # Stands in for a scheduler that finishes every launched control at once,
  # with the next of +statuses+ (the last one repeats).
  def gate(*statuses, downstream: self.downstream)
    outcomes = statuses.map { |status| result(status) }
    built = nil
    launcher = lambda do |key, detected|
      launches << detected
      built.control_finished(key, outcomes.size > 1 ? outcomes.shift : outcomes.first)
    end
    built = described_class.new(downstream:, control_run: Henitai::ControlRun.new, launcher:)
  end

  it "delivers a detection unchanged once its group's control passes" do
    killed = mutant(subject_a, :killed)

    gate(:survived).progress(killed, scenario_result: result(:killed))

    expect(delivered).to eq([[killed, :killed, :killed]])
  end

  it "reclassifies mutant and result when the control fails" do
    killed = mutant(subject_a, :killed)

    gate(:killed).progress(killed, scenario_result: result(:killed))

    expect(delivered).to eq([[killed, :compile_error, :compile_error]])
  end

  it "keeps the captured output and gives the result the mutant's reason" do
    killed = mutant(subject_a, :killed)
    received = nil
    sink = Class.new { define_method(:progress) { |_mutant, scenario_result: nil| received = scenario_result } }.new

    gate(:killed, downstream: sink).progress(killed, scenario_result: result(:killed))

    expect([received.stdout, received.status_reason]).to eq(["out", killed.status_reason])
  end

  it "runs one control per subject and test-file set and applies its outcome to later detections",
     :aggregate_failures do
    gate = gate(:killed, :survived)
    first = mutant(subject_a, :killed)
    second = mutant(subject_a, :timeout)
    other = mutant(subject_b, :killed)

    [first, second, other].each { |detected| gate.progress(detected, scenario_result: result(detected.status)) }

    expect(launches).to eq([first, other])
    expect(delivered.map { |entry| entry[1] }).to eq(%i[compile_error compile_error killed])
  end

  it "passes verdicts that need no control straight through", :aggregate_failures do
    cached = mutant(subject_a, :killed).tap { |built| built.from_cache = true }
    gate = gate(:killed)

    [mutant(subject_a, :survived), mutant(subject_a, :no_coverage), cached].each { |entry| gate.progress(entry) }

    expect(launches).to be_empty
    expect(delivered.map { |entry| entry[1] }).to eq(%i[survived no_coverage killed])
  end

  it "verifies detections even without a downstream observer" do
    killed = mutant(subject_a, :killed)

    gate(:killed, downstream: nil).progress(killed)

    expect(killed.status).to eq(:compile_error)
  end

  it "reports how many groups it verified, how many failed and how many verdicts it reclassified" do
    gate = gate(:killed, :survived)
    [mutant(subject_a, :killed), mutant(subject_a, :killed), mutant(subject_b, :killed)]
      .each { |detected| gate.progress(detected) }

    expect(gate.stats).to eq(verified: 2, failed: 1, reclassified: 2)
  end

  describe "with a deferred control" do
    def deferred_gate
      launched = []
      gate = described_class.new(downstream:, control_run: Henitai::ControlRun.new,
                                 launcher: ->(key, detected) { launched << [key, detected] })
      [gate, launched]
    end

    it "holds detections until the control finishes" do
      gate, launched = deferred_gate
      killed = mutant(subject_a, :killed)
      gate.progress(killed, scenario_result: result(:killed))
      held = delivered.dup

      gate.control_finished(launched.first.first, result(:survived))

      expect([held, delivered]).to eq([[], [[killed, :killed, :killed]]])
    end

    it "launches one control per group while it is pending" do
      gate, launched = deferred_gate
      2.times { gate.progress(mutant(subject_a, :killed)) }

      expect(launched.size).to eq(1)
    end

    it "drops held detections and reports how many" do
      gate, = deferred_gate
      2.times { gate.progress(mutant(subject_a, :killed)) }

      expect([gate.drop_held, delivered]).to eq([2, []])
    end
  end
end
