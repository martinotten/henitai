# frozen_string_literal: true

require "spec_helper"
require "parser/current"

RSpec.describe Henitai::Reporter::Terminal do
  def build_mutant(status:, survived: false, attributes: {})
    Struct.new(:status, :survived, :operator, :location, :original_node, :mutated_node) do
      def survived?
        survived
      end
    end.new(
      status,
      survived,
      attributes[:operator],
      attributes[:location],
      attributes[:original_node],
      attributes[:mutated_node]
    )
  end

  def build_config(thresholds: { high: 80, low: 60 })
    Struct.new(:thresholds).new(thresholds)
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

  def score_summary_line(
    mutation_score:,
    mutation_score_indicator:,
    equivalence_uncertainty:,
    color_code: nil
  )
    line = format(
      "MS %<ms>s | MSI %<msi>s | Equivalence uncertainty %<uncertainty>s",
      ms: mutation_score,
      msi: mutation_score_indicator,
      uncertainty: equivalence_uncertainty
    )
    return line unless color_code

    "\e[#{color_code}m#{line}\e[0m"
  end

  def parse_node(source)
    Parser::CurrentRuby.parse(source)
  end

  def survived_detail_mutant(file:, line:, operator:, original_source:, mutated_source:)
    build_mutant(
      status: :survived,
      survived: true,
      attributes: {
        operator:,
        location: { file:, start_line: line },
        original_node: parse_node(original_source),
        mutated_node: parse_node(mutated_source)
      }
    )
  end

  def first_survived_detail_mutant
    survived_detail_mutant(
      file: "lib/foo.rb",
      line: 12,
      operator: "ArithmeticOperator",
      original_source: "1",
      mutated_source: "2"
    )
  end

  def second_survived_detail_mutant
    survived_detail_mutant(
      file: "lib/bar.rb",
      line: 7,
      operator: "BooleanLiteral",
      original_source: "true",
      mutated_source: "false"
    )
  end

  def survived_detail_mutants
    [first_survived_detail_mutant, second_survived_detail_mutant]
  end

  def survived_detail_scoring_summary
    {
      mutation_score: 75.0,
      mutation_score_indicator: 12.5,
      equivalence_uncertainty: "~10-15% of live mutants"
    }
  end

  def build_survived_detail_result
    build_result(
      mutants: survived_detail_mutants,
      scoring_summary: survived_detail_scoring_summary,
      duration: 12.34
    )
  end

  it "prints progress glyphs for known statuses" do
    reporter = described_class.new(config: build_config)
    mutants = %i[killed survived timeout ignored].map { |status| build_mutant(status:) }

    expect { mutants.each { |mutant| reporter.progress(mutant) } }
      .to output("·STI").to_stdout
  end

  it "does not print a glyph for unknown statuses" do
    reporter = described_class.new(config: build_config)

    expect { reporter.progress(build_mutant(status: :pending)) }.not_to output.to_stdout
  end

  it "prints a summary table with score, counts, and duration" do
    reporter = described_class.new(config: build_config)
    result = build_result(
      mutants: %i[killed timeout no_coverage].map { |status| build_mutant(status:) },
      scoring_summary: {
        mutation_score: 75.0,
        mutation_score_indicator: 12.5,
        equivalence_uncertainty: "~10-15% of live mutants"
      },
      duration: 12.34
    )

    expected_output = <<~OUTPUT
      Mutation testing summary
      #{score_summary_line(
        mutation_score: '75.00%',
        mutation_score_indicator: '12.50%',
        equivalence_uncertainty: '~10-15% of live mutants',
        color_code: '33'
      )}
      #{summary_row('Killed', 1)}
      #{summary_row('Survived', 0)}
      #{summary_row('Timeout', 1)}
      #{summary_row('No coverage', 1)}
      #{summary_row('Duration', '12.34s')}
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end

  it "colors the score line green when the score meets the high threshold" do
    reporter = described_class.new(config: build_config)
    result = build_result(
      mutants: [],
      scoring_summary: {
        mutation_score: 80.0,
        mutation_score_indicator: 10.0,
        equivalence_uncertainty: nil
      },
      duration: 0.0
    )

    expected_output = <<~OUTPUT
      Mutation testing summary
      #{score_summary_line(
        mutation_score: '80.00%',
        mutation_score_indicator: '10.00%',
        equivalence_uncertainty: 'n/a',
        color_code: '32'
      )}
      #{summary_row('Killed', 0)}
      #{summary_row('Survived', 0)}
      #{summary_row('Timeout', 0)}
      #{summary_row('No coverage', 0)}
      #{summary_row('Duration', '0.00s')}
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end

  it "colors the score line yellow when the score meets the low threshold" do
    reporter = described_class.new(config: build_config)
    result = build_result(
      mutants: [],
      scoring_summary: {
        mutation_score: 60.0,
        mutation_score_indicator: 10.0,
        equivalence_uncertainty: nil
      },
      duration: 0.0
    )

    expected_output = <<~OUTPUT
      Mutation testing summary
      #{score_summary_line(
        mutation_score: '60.00%',
        mutation_score_indicator: '10.00%',
        equivalence_uncertainty: 'n/a',
        color_code: '33'
      )}
      #{summary_row('Killed', 0)}
      #{summary_row('Survived', 0)}
      #{summary_row('Timeout', 0)}
      #{summary_row('No coverage', 0)}
      #{summary_row('Duration', '0.00s')}
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end

  it "colors the score line red when the score is below the low threshold" do
    reporter = described_class.new(config: build_config)
    result = build_result(
      mutants: [],
      scoring_summary: {
        mutation_score: 50.0,
        mutation_score_indicator: 10.0,
        equivalence_uncertainty: nil
      },
      duration: 0.0
    )

    expected_output = <<~OUTPUT
      Mutation testing summary
      #{score_summary_line(
        mutation_score: '50.00%',
        mutation_score_indicator: '10.00%',
        equivalence_uncertainty: 'n/a',
        color_code: '31'
      )}
      #{summary_row('Killed', 0)}
      #{summary_row('Survived', 0)}
      #{summary_row('Timeout', 0)}
      #{summary_row('No coverage', 0)}
      #{summary_row('Duration', '0.00s')}
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
      #{score_summary_line(
        mutation_score: 'n/a',
        mutation_score_indicator: 'n/a',
        equivalence_uncertainty: 'n/a'
      )}
      #{summary_row('Killed', 0)}
      #{summary_row('Survived', 0)}
      #{summary_row('Timeout', 0)}
      #{summary_row('No coverage', 0)}
      #{summary_row('Duration', '0.00s')}
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end

  it "prints survived mutant details after the summary block" do
    reporter = described_class.new(config: build_config)
    result = build_survived_detail_result

    expected_output = <<~OUTPUT
      Mutation testing summary
      #{score_summary_line(
        mutation_score: '75.00%',
        mutation_score_indicator: '12.50%',
        equivalence_uncertainty: '~10-15% of live mutants',
        color_code: '33'
      )}
      #{summary_row('Killed', 0)}
      #{summary_row('Survived', 2)}
      #{summary_row('Timeout', 0)}
      #{summary_row('No coverage', 0)}
      #{summary_row('Duration', '12.34s')}

      Survived mutants
      lib/foo.rb:12 ArithmeticOperator
      - 1
      + 2
      lib/bar.rb:7 BooleanLiteral
      - true
      + false
    OUTPUT

    expect { reporter.report(result) }.to output(expected_output).to_stdout
  end
end
