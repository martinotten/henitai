# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Reporter::Json do
  def build_config(reports_dir:)
    Struct.new(:reports_dir).new(reports_dir)
  end

  def build_result(schema:)
    Struct.new(:to_stryker_schema).new(schema)
  end

  it "writes mutation-report.json to the configured reports directory" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "nested", "reports")
      schema = {
        schemaVersion: "1.0",
        thresholds: { high: 80, low: 60 },
        files: {}
      }

      described_class.new(config: build_config(reports_dir:)).report(build_result(schema:))

      report_path = File.join(reports_dir, "mutation-report.json")

      expect(File).to exist(report_path)
    end
  end

  it "writes the schema payload as JSON" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "nested", "reports")
      schema = {
        schemaVersion: "1.0",
        thresholds: { high: 80, low: 60 },
        files: {}
      }

      described_class.new(config: build_config(reports_dir:)).report(build_result(schema:))

      report_path = File.join(reports_dir, "mutation-report.json")

      expect(JSON.parse(File.read(report_path), symbolize_names: true)).to eq(schema)
    end
  end
end
