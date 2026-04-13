# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::CoverageReportReader do
  it "builds a coverage map from a SimpleCov resultset" do
    Dir.mktmpdir do |dir|
      report_path = File.join(dir, ".resultset.json")
      File.write(
        report_path,
        {
          "RSpec" => {
            "coverage" => {
              "/tmp/sample.rb" => {
                "lines" => [nil, 1, 0, 3]
              }
            }
          },
          "Other" => {
            "coverage" => {
              "/tmp/sample.rb" => {
                "lines" => [nil, 0, 2, nil]
              },
              "/tmp/other.rb" => {
                "lines" => [1, nil]
              }
            }
          }
        }.to_json
      )

      coverage = described_class.new.coverage_lines_by_file(report_path)

      expect(coverage).to eq(
        "/tmp/other.rb" => [1],
        "/tmp/sample.rb" => [2, 3, 4]
      )
    end
  end

  it "builds a per-test coverage map from formatter output" do
    Dir.mktmpdir do |dir|
      report_path = File.join(dir, "coverage", "henitai_per_test.json")
      FileUtils.mkdir_p(File.dirname(report_path))
      File.write(
        report_path,
        {
          File.expand_path("spec/models/sample_spec.rb", dir) => {
            File.expand_path("lib/sample.rb", dir) => [5, 1, 5, 3],
            File.expand_path("lib/other.rb", dir) => [2]
          },
          File.expand_path("spec/models/other_spec.rb", dir) => {
            File.expand_path("lib/sample.rb", dir) => [2]
          }
        }.to_json
      )

      coverage = described_class.new.test_lines_by_file(report_path)

      expect(coverage).to eq(
        File.expand_path("spec/models/other_spec.rb", dir) => {
          File.expand_path("lib/sample.rb", dir) => [2]
        },
        File.expand_path("spec/models/sample_spec.rb", dir) => {
          File.expand_path("lib/other.rb", dir) => [2],
          File.expand_path("lib/sample.rb", dir) => [1, 3, 5]
        }
      )
    end
  end
end
