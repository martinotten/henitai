# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Henitai::Reporter::DryRun do
  def build_mutant(status:, **attributes)
    defaults = {
      subject: "Sample#answer", operator: :ArithmeticOperator,
      description: "replaced + with -", file: "lib/sample.rb", start_line: 3,
      ignore_reason: nil
    }
    values = defaults.merge(attributes)
    Struct.new(:status, :subject, :operator, :description, :location, :ignore_reason).new(
      status,
      Struct.new(:expression).new(values[:subject]),
      values[:operator],
      values[:description],
      { file: values[:file], start_line: values[:start_line], end_line: values[:start_line] },
      values[:ignore_reason]
    )
  end

  def report(mutants)
    io = StringIO.new
    config = Struct.new(:reports_dir).new("reports")
    described_class.new(config:, io:).report(Struct.new(:mutants).new(mutants))
    io.string
  end

  it "groups mutants per subject with one line per mutant" do
    output = report(
      [
        build_mutant(status: :pending),
        build_mutant(status: :pending, subject: "Sample#other", start_line: 9)
      ]
    )

    expect(output).to eq(<<~LISTING)
      Dry run: 2 mutants (no tests executed)

      Sample#answer
        ArithmeticOperator — replaced + with -  lib/sample.rb:3  [pending]

      Sample#other
        ArithmeticOperator — replaced + with -  lib/sample.rb:9  [pending]

      Summary: pending 2
    LISTING
  end

  it "shows ignored mutants with their reason when one is attached" do
    output = report(
      [build_mutant(status: :ignored, ignore_reason: "log-format noise")]
    )

    expect(output).to include("[ignored] (log-format noise)")
  end

  it "counts every status in the summary" do
    output = report(
      [
        build_mutant(status: :pending),
        build_mutant(status: :ignored),
        build_mutant(status: :ignored)
      ]
    )

    expect(output).to include("Summary: pending 1 | ignored 2")
  end

  it "prints an empty listing for zero mutants" do
    expect(report([])).to eq(<<~LISTING)
      Dry run: 0 mutants (no tests executed)

      Summary: no mutants
    LISTING
  end
end
