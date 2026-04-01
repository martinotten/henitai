# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Reporter::Terminal do
  def build_mutant(status)
    Struct.new(:status).new(status)
  end

  def build_config
    Struct.new(:thresholds).new({})
  end

  def build_result(mutants:, scoring_summary:, duration:)
    Struct.new(:mutants, :scoring_summary, :duration).new(
      mutants,
      scoring_summary,
      duration
    )
  end

  def summary_row(label, value)
    "#{label.ljust(12)} #{value}"
  end

  it "prints progress glyphs for known statuses" do
    reporter = described_class.new(config: build_config)
    mutants = %i[killed survived timeout ignored].map { |status| build_mutant(status) }

    expect { mutants.each { |mutant| reporter.progress(mutant) } }
      .to output("·STI").to_stdout
  end

  it "does not print a glyph for unknown statuses" do
    reporter = described_class.new(config: build_config)

    expect { reporter.progress(build_mutant(:pending)) }.not_to output.to_stdout
  end

  it "prints a summary table with score, counts, and duration" do
    reporter = described_class.new(config: build_config)
    result = build_result(
      mutants: %i[killed survived timeout no_coverage].map { |status| build_mutant(status) },
      scoring_summary: {
        mutation_score: 75.0,
        mutation_score_indicator: 12.5,
        equivalence_uncertainty: "~10-15% of live mutants"
      },
      duration: 12.34
    )

    expected_output = <<~OUTPUT
      Mutation testing summary
      MS 75.00% | MSI 12.50% | Equivalence uncertainty ~10-15% of live mutants
      #{summary_row('Killed', 1)}
      #{summary_row('Survived', 1)}
      #{summary_row('Timeout', 1)}
      #{summary_row('No coverage', 1)}
      #{summary_row('Duration', '12.34s')}
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end

  it "prints n/a when the scoring summary does not include live mutants" do
    reporter = described_class.new(config: build_config)
    result = build_result(
      mutants: [],
      scoring_summary: {
        mutation_score: nil,
        mutation_score_indicator: nil,
        equivalence_uncertainty: nil
      },
      duration: 0.0
    )

    expected_output = <<~OUTPUT
      Mutation testing summary
      MS n/a | MSI n/a | Equivalence uncertainty n/a
      #{summary_row('Killed', 0)}
      #{summary_row('Survived', 0)}
      #{summary_row('Timeout', 0)}
      #{summary_row('No coverage', 0)}
      #{summary_row('Duration', '0.00s')}
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end
end
