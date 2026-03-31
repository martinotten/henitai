# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Result do
  def mutant(status:, killed: false, duration: nil)
    instance_double(
      Henitai::Mutant,
      status:,
      killed?: killed,
      duration:
    )
  end

  def result(mutants)
    described_class.new(
      mutants:,
      started_at: Time.at(0),
      finished_at: Time.at(1)
    )
  end

  it "returns nil and a score when evaluating mutation score" do
    expect(
      [
        result([mutant(status: :ignored), mutant(status: :equivalent)]).mutation_score,
        result([mutant(status: :killed), mutant(status: :survived)]).mutation_score
      ]
    ).to eq([nil, 50.0])
  end

  it "returns nil and a score when evaluating mutation score indicator" do
    expect(
      [
        result([]).mutation_score_indicator,
        result([mutant(status: :killed, killed: true), mutant(status: :survived)]).mutation_score_indicator
      ]
    ).to eq([nil, 50.0])
  end

  it "handles nil and present durations" do
    sample_result = result([])

    expect(
      [
        sample_result.send(:duration_for, mutant(status: :pending)),
        sample_result.send(:duration_for, mutant(status: :pending, duration: 1.234))
      ]
    ).to eq([nil, 1234])
  end
end
