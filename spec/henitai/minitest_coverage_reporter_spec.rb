# frozen_string_literal: true

require "json"
require "minitest"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::MinitestCoverageReporter do
  def build_result(absolute_path)
    Struct.new(:source_location).new([absolute_path, 5])
  end

  def coverage_snapshot(source_lines:)
    {
      File.expand_path("lib/sample.rb") => { "lines" => source_lines }
    }
  end

  it "writes per-test coverage keyed by the project-relative test path" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        reporter = described_class.new

        allow(Coverage).to receive(:peek_result).and_return(
          coverage_snapshot(source_lines: [nil, 1, 0, 3])
        )

        reporter.record(build_result(File.join(Dir.pwd, "test", "sample_test.rb")))
        reporter.report

        report_path = File.join("coverage", "henitai_per_test.json")
        expect(JSON.parse(File.read(report_path))).to eq(
          "test/sample_test.rb" => {
            File.expand_path("lib/sample.rb") => [2, 4]
          }
        )
      end
    end
  end

  it "does not write a report when no tests have been recorded" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        reporter = described_class.new

        reporter.report

        expect(File.exist?(File.join("coverage", "henitai_per_test.json"))).to be(false)
      end
    end
  end

  it "passes an out-of-project path through unchanged as the test key" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        reporter = described_class.new
        outside_path = "/other/project/test/sample_test.rb"

        allow(Coverage).to receive(:peek_result).and_return(
          coverage_snapshot(source_lines: [nil, 1, 0])
        )

        reporter.record(build_result(outside_path))
        reporter.report

        report_path = File.join("coverage", "henitai_per_test.json")
        report = JSON.parse(File.read(report_path))
        expect(report.keys).to eq([outside_path])
      end
    end
  end
end
