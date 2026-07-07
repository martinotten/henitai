# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Henitai::Reporter::Github do
  def build_mutant(status:, operator: :ArithmeticOperator, description: "replaced + with -",
                   file: "lib/foo.rb", start_line: 42)
    Struct.new(:status, :operator, :description, :location) do
      def survived? = status == :survived
    end.new(status, operator, description, { file:, start_line:, end_line: start_line })
  end

  def build_result(mutants)
    Struct.new(:mutants).new(mutants)
  end

  def build_config
    Struct.new(:reports_dir).new("reports")
  end

  def report(mutants)
    io = StringIO.new
    described_class.new(config: build_config, io:).report(build_result(mutants))
    io.string
  end

  it "emits one ::warning workflow command per survived mutant" do
    output = report([build_mutant(status: :survived)])

    expect(output).to eq(
      "::warning file=lib/foo.rb,line=42::Survived mutant: ArithmeticOperator — replaced + with -\n"
    )
  end

  it "emits nothing for killed, ignored, no-coverage and timeout mutants" do
    output = report(
      %i[killed ignored no_coverage timeout].map { |status| build_mutant(status:) }
    )

    expect(output).to be_empty
  end

  it "emits nothing for an empty result" do
    expect(report([])).to be_empty
  end

  it "emits one line per survivor when several survive" do
    output = report(
      [
        build_mutant(status: :survived, file: "lib/a.rb", start_line: 1),
        build_mutant(status: :killed),
        build_mutant(status: :survived, file: "lib/b.rb", start_line: 9)
      ]
    )

    expect(output.lines).to eq(
      [
        "::warning file=lib/a.rb,line=1::Survived mutant: ArithmeticOperator — replaced + with -\n",
        "::warning file=lib/b.rb,line=9::Survived mutant: ArithmeticOperator — replaced + with -\n"
      ]
    )
  end

  it "escapes %, newline and carriage return in the message payload" do
    output = report(
      [build_mutant(status: :survived, description: "100% broken\nline two\rend :: literal")]
    )

    expect(output).to eq(
      "::warning file=lib/foo.rb,line=42::" \
      "Survived mutant: ArithmeticOperator — 100%25 broken%0Aline two%0Dend :: literal\n"
    )
  end

  it "prints repo-relative paths for absolute file locations" do
    absolute = File.join(Dir.pwd, "lib/foo.rb")
    output = report([build_mutant(status: :survived, file: absolute)])

    expect(output).to include("file=lib/foo.rb,")
  end

  it "defaults its output IO to $stdout" do
    expect do
      described_class.new(config: build_config).report(build_result([build_mutant(status: :survived)]))
    end.to output(a_string_including("::warning file=lib/foo.rb")).to_stdout
  end
end
