# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::PerTestCoverageCollector do
  def report_path
    File.join(ENV.fetch("HENITAI_REPORTS_DIR", "coverage"), "henitai_per_test.json")
  end

  def with_env(key, value)
    original = ENV.fetch(key, nil)
    ENV[key] = value
    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end

  def coverage_snapshot(source_lines:)
    {
      File.expand_path("lib/sample.rb") => {
        "lines" => source_lines
      }
    }
  end

  it "writes nested per-test coverage data to the report path" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        collector = described_class.new

        allow(Coverage).to receive(:peek_result).and_return(
          coverage_snapshot(source_lines: [nil, 1, 0, 3])
        )

        collector.record_test("test/sample_test.rb")
        collector.write_report

        expect(JSON.parse(File.read(report_path))).to eq(
          "test/sample_test.rb" => {
            File.expand_path("lib/sample.rb") => [2, 4]
          }
        )
      end
    end
  end

  it "creates the output directory when needed" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        collector = described_class.new

        allow(Coverage).to receive(:peek_result).and_return(
          coverage_snapshot(source_lines: [nil, 1, 0])
        )

        collector.record_test("test/sample_test.rb")
        collector.write_report

        expect(File).to exist(report_path)
      end
    end
  end

  it "writes the report under the ENV-configured output dir" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        collector = described_class.new
        reports_dir = File.join(dir, "custom-reports")

        with_env("HENITAI_REPORTS_DIR", reports_dir) do
          allow(Coverage).to receive(:peek_result).and_return(
            coverage_snapshot(source_lines: [nil, 1, 0])
          )

          collector.record_test("test/sample_test.rb")
          collector.write_report
        end

        expect(File).to exist(File.join(reports_dir, "henitai_per_test.json"))
      end
    end
  end

  it "handles symbol-keyed coverage hashes from Coverage.peek_result" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        collector = described_class.new

        allow(Coverage).to receive(:peek_result).and_return(
          File.expand_path("lib/sample.rb") => {
            lines: [nil, 1, 0, 3],
            branches: {},
            methods: {}
          }
        )

        collector.record_test("test/sample_test.rb")
        collector.write_report

        expect(JSON.parse(File.read(report_path))).to eq(
          "test/sample_test.rb" => {
            File.expand_path("lib/sample.rb") => [2, 4]
          }
        )
      end
    end
  end

  it "canonicalizes relative source file keys when writing the report" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        collector = described_class.new

        allow(Coverage).to receive(:peek_result).and_return(
          "lib/sample.rb" => [nil, 1, 0, 3]
        )

        collector.record_test("test/sample_test.rb")
        collector.write_report

        expect(JSON.parse(File.read(report_path))).to eq(
          "test/sample_test.rb" => {
            File.expand_path("lib/sample.rb") => [2, 4]
          }
        )
      end
    end
  end

  it "emits a warning to stderr once when coverage is unavailable" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        collector = described_class.new

        allow(Coverage).to receive(:peek_result).and_raise(StandardError)

        expect do
          collector.record_test("test/sample_test.rb")
          collector.record_test("test/sample_test.rb")
          collector.write_report
        end.to output(
          "Per-test coverage unavailable; skipping coverage formatter output\n"
        ).to_stderr

        expect(File.exist?("coverage/henitai_per_test.json")).to be(false)
      end
    end
  end

  it "excludes test/ files from source coverage tracking" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        collector = described_class.new

        allow(Coverage).to receive(:peek_result).and_return(
          File.expand_path("lib/sample.rb") => [nil, 1, 0],
          File.expand_path("test/sample_test.rb") => [nil, 1, 1]
        )

        collector.record_test("test/sample_test.rb")
        collector.write_report

        report = JSON.parse(File.read(report_path))
        source_files = report.values.flat_map(&:keys)
        expect(source_files).not_to include(match(%r{/test/}))
      end
    end
  end

  it "excludes spec/ files from source coverage tracking" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        collector = described_class.new

        allow(Coverage).to receive(:peek_result).and_return(
          File.expand_path("lib/sample.rb") => [nil, 1, 0],
          File.expand_path("spec/sample_spec.rb") => [nil, 1, 1]
        )

        collector.record_test("test/sample_test.rb")
        collector.write_report

        report = JSON.parse(File.read(report_path))
        source_files = report.values.flat_map(&:keys)
        expect(source_files).not_to include(match(%r{/spec/}))
      end
    end
  end
end
