# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"

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

  it "filters using a real CoverageReportReader parsing an on-disk per-test report" do
    Dir.mktmpdir do |dir|
      file = File.expand_path("lib/sample.rb")
      File.write(
        File.join(dir, "henitai_per_test.json"),
        JSON.generate(
          "spec/foo_spec.rb" => { file => [2] },
          "spec/bar_spec.rb" => { file => [4] }
        )
      )
      selector = described_class.new

      expect(
        selector.filter(
          ["spec/foo_spec.rb", "spec/bar_spec.rb"],
          build_mutant(file),
          reports_dir: dir
        )
      ).to eq(["spec/foo_spec.rb"])
    end
  end

  it "falls back to all candidates when the real reader finds no per-test report" do
    Dir.mktmpdir do |dir|
      selector = described_class.new

      expect(
        selector.filter(
          ["spec/foo_spec.rb", "spec/bar_spec.rb"],
          build_mutant(File.expand_path("lib/sample.rb")),
          reports_dir: dir
        )
      ).to eq(["spec/foo_spec.rb", "spec/bar_spec.rb"])
    end
  end

  it "falls back to all candidates when the mutant location is incomplete" do
    reader = instance_double(Henitai::CoverageReportReader)
    selector = described_class.new(coverage_report_reader: reader)
    mutant = build_mutant(nil)
    allow(reader).to receive(:test_lines_by_file).and_return(
      "spec/foo_spec.rb" => { File.expand_path("lib/sample.rb") => [2] }
    )

    expect(
      selector.filter(
        ["spec/foo_spec.rb", "spec/bar_spec.rb"],
        mutant,
        reports_dir: "coverage"
      )
    ).to eq(["spec/foo_spec.rb", "spec/bar_spec.rb"])
  end

  it "does not read coverage when there are no candidates" do
    reader = instance_double(Henitai::CoverageReportReader)
    selector = described_class.new(coverage_report_reader: reader)
    allow(reader).to receive(:test_lines_by_file)

    selector.filter([], build_mutant(File.expand_path("lib/sample.rb")), reports_dir: "coverage")

    expect(reader).not_to have_received(:test_lines_by_file)
  end
end
