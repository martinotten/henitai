# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::KillHistory do
  subject(:history) { described_class.new }

  def result(status, killing_tests)
    Henitai::ScenarioExecutionResult.new(status:, stdout: "", stderr: "", log_path: nil, killing_tests:)
  end

  it "counts each kill toward every test file that failed" do
    history.progress(:mutant, scenario_result: result(:killed, %w[/a_spec.rb /b_spec.rb]))
    history.progress(:mutant, scenario_result: result(:killed, %w[/a_spec.rb]))

    expect([history.fetch("/a_spec.rb"), history.fetch("/b_spec.rb")]).to eq([2, 1])
  end

  it "ignores verdicts other than killed" do
    %i[survived timeout runtime_error compile_error].each do |status|
      history.progress(:mutant, scenario_result: result(status, %w[/a_spec.rb]))
    end

    expect(history.fetch("/a_spec.rb", 0)).to eq(0)
  end

  it "ignores progress without a scenario result" do
    history.progress(:mutant)

    expect(history.fetch("/a_spec.rb", :none)).to eq(:none)
  end
end
