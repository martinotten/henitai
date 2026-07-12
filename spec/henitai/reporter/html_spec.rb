# frozen_string_literal: true

require "fileutils"
require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Reporter::Html do
  def build_config(reports_dir:)
    Struct.new(:reports_dir).new(reports_dir)
  end

  def build_result(schema:, authoritative: true)
    Struct.new(:to_stryker_schema, :authoritative?).new(schema, authoritative)
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

  it "embeds the same merged schema as the canonical JSON report when not authoritative" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "reports")
      FileUtils.mkdir_p(reports_dir)
      canonical_path = File.join(reports_dir, "mutation-report.json")
      File.write(canonical_path, JSON.pretty_generate(
                                   { schemaVersion: "1.0", thresholds: { high: 80, low: 60 },
                                     files: { "old.rb" => { language: "ruby", source: "", mutants: [
                                       { id: "1", stableId: "old1", mutatorName: "X", status: "Killed" }
                                     ] } } }
                                 ))
      schema = { schemaVersion: "1.0", thresholds: { high: 80, low: 60 },
                 files: { "new.rb" => { language: "ruby", source: "", mutants: [
                   { id: "2", stableId: "new1", mutatorName: "X", status: "Killed" }
                 ] } } }

      result = build_result(schema:, authoritative: false)
      Henitai::Reporter::Json.new(config: build_config(reports_dir:)).report(result)
      described_class.new(config: build_config(reports_dir:)).report(result)

      html = File.read(File.join(reports_dir, "mutation-report.html"))
      embedded = JSON.parse(JSON.generate(extract_report_json(html)))
      canonical = JSON.parse(File.read(canonical_path))

      expect(canonical).to eq(embedded)
    end
  end

  it "merges existing source files for a non-authoritative run" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        reports_dir = File.join(dir, "reports")
        File.write("old.rb", "1 - 0\n")
        File.write("new.rb", "1 - 0\n")
        FileUtils.mkdir_p(reports_dir)
        File.write(
          File.join(reports_dir, "mutation-report.json"),
          JSON.pretty_generate(
            schemaVersion: "1.0",
            thresholds: { high: 80, low: 60 },
            files: { "old.rb" => {
              language: "ruby", source: "", mutants: [{ stableId: "old" }]
            } }
          )
        )
        schema = {
          schemaVersion: "1.0",
          thresholds: { high: 80, low: 60 },
          files: { "new.rb" => {
            language: "ruby", source: "", mutants: [{ stableId: "new" }]
          } }
        }

        described_class.new(config: build_config(reports_dir:)).report(
          build_result(schema:, authoritative: false)
        )

        html = File.read(File.join(reports_dir, "mutation-report.html"))
        expect(extract_report_json(html)[:files].keys).to contain_exactly(:"old.rb", :"new.rb")
      end
    end
  end
end
