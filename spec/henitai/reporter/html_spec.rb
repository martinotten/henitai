# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Reporter::Html do
  def build_config(reports_dir:)
    Struct.new(:reports_dir).new(reports_dir)
  end

  def build_result(schema:)
    Struct.new(:to_stryker_schema).new(schema)
  end

  def extract_report_json(html)
    match = html.match(
      %r{<script type="application/json" id="henitai-report-data">(.*?)</script>}m
    )
    JSON.parse(match[1], symbolize_names: true)
  end

  it "writes mutation-report.html to the configured reports directory" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "nested", "reports")
      schema = {
        schemaVersion: "1.0",
        thresholds: { high: 80, low: 60 },
        files: {}
      }

      described_class.new(config: build_config(reports_dir:)).report(build_result(schema:))

      report_path = File.join(reports_dir, "mutation-report.html")

      expect(File).to exist(report_path)
    end
  end

  it "embeds the report data and mutation-testing-elements loader" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "nested", "reports")
      schema = {
        schemaVersion: "1.0",
        thresholds: { high: 80, low: 60 },
        files: {}
      }

      described_class.new(config: build_config(reports_dir:)).report(build_result(schema:))

      report_path = File.join(reports_dir, "mutation-report.html")
      html = File.read(report_path)

      expect(
        [
          html.include?("https://www.unpkg.com/mutation-testing-elements"),
          extract_report_json(html)
        ]
      ).to eq([true, schema])
    end
  end
end
