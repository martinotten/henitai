# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::PerTestCoverageSelector do
  def build_mutant(file)
    Struct.new(:location).new(
      {
        file:,
        start_line: 2,
        end_line: 2
      }
    )
  end

  it "filters tests using the coverage report reader" do
    file = File.expand_path("lib/sample.rb")
    reader = instance_double(Henitai::CoverageReportReader)
    selector = described_class.new(coverage_report_reader: reader)

    allow(reader).to receive(:test_lines_by_file).and_return(
      "spec/foo_spec.rb" => {
        file => [2]
      },
      "spec/bar_spec.rb" => {
        file => [4]
      }
    )

    expect(
      selector.filter(
        ["spec/foo_spec.rb", "spec/bar_spec.rb"],
        build_mutant(file),
        reports_dir: "coverage"
      )
    ).to eq(["spec/foo_spec.rb"])
  end
end
