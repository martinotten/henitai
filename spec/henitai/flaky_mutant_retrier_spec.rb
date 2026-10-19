# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::FlakyMutantRetrier do
  subject(:retrier) { described_class.new(flaky_tests: flaky_tests, max_retries: 3) }

  let(:mutant) { instance_double(Henitai::Mutant) }
  let(:integration) { instance_double(Henitai::Integration::Base, run_mutant: nil) }
  let(:flaky_tests) { Henitai::FlakyTestRegistry.new(["/app/spec/flaky_spec.rb"]) }
  let(:result_class) { Henitai::ScenarioExecutionResult }

  def result(status, killing_tests: [])
    result_class.new(status: status, stdout: "", stderr: "", log_path: nil, killing_tests: killing_tests)
  end

  def run_with(*results)
    allow(integration).to receive(:run_mutant).and_return(*results)
    retrier.run(mutant: mutant, integration: integration, test_files: ["a"], timeout: 1)
  end

  it "returns survived results without retrying" do
    run_with(result(:survived))

    expect(integration).to have_received(:run_mutant).once
  end

  it "does not retry a kill whose killing tests are not flaky" do
    run_with(result(:killed, killing_tests: ["/app/spec/stable_spec.rb"]))

    expect(integration).to have_received(:run_mutant).once
  end

  it "returns the kill itself when it needs no retry" do
    stable = result(:killed, killing_tests: ["/app/spec/stable_spec.rb"])

    expect(run_with(stable)).to be(stable)
  end

  it "retries a flaky-only kill up to the retry budget" do
    flaky = result(:killed, killing_tests: ["/app/spec/flaky_spec.rb"])
    run_with(flaky, flaky, flaky, flaky)

    expect(integration).to have_received(:run_mutant).exactly(4).times
  end

  it "reports survived when a retry of a flaky-only kill survives" do
    flaky = result(:killed, killing_tests: ["/app/spec/flaky_spec.rb"])
    expect(run_with(flaky, result(:survived))).to have_attributes(status: :survived)
  end

  it "counts mutants whose kill was re-checked" do
    run_with(result(:killed, killing_tests: ["/app/spec/flaky_spec.rb"]), result(:killed))
    expect(retrier.retried_count).to eq(1)
  end

  it "does not retry when the flaky set is empty" do
    retrier = described_class.new(flaky_tests: Henitai::FlakyTestRegistry.new([]), max_retries: 3)
    allow(integration).to receive(:run_mutant).and_return(result(:killed, killing_tests: ["/app/spec/flaky_spec.rb"]))
    retrier.run(mutant: mutant, integration: integration, test_files: ["a"], timeout: 1)
    expect(integration).to have_received(:run_mutant).once
  end

  it "accepts a bare status symbol from the integration" do
    allow(integration).to receive(:run_mutant).and_return(:survived)
    expect(retrier.run(mutant: mutant, integration: integration, test_files: ["a"], timeout: 1)).to eq(:survived)
  end
end
