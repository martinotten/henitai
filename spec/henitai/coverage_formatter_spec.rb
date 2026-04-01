# frozen_string_literal: true

require "json"
require "spec_helper"
require "stringio"
require "tmpdir"

RSpec.describe Henitai::CoverageFormatter do
  def build_notification(file_path)
    example = Struct.new(:metadata).new({ file_path: file_path })
    Struct.new(:example).new(example)
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
        formatter = described_class.new(StringIO.new)
        notification = build_notification("spec/models/sample_spec.rb")

        allow(Coverage).to receive(:peek_result).and_return(
          coverage_snapshot(source_lines: [nil, 1, 0, 3])
        )

        formatter.example_finished(notification)
        formatter.dump_summary(nil)

        expect(JSON.parse(File.read("coverage/henitai_per_test.json"))).to eq(
          "spec/models/sample_spec.rb" => {
            File.expand_path("lib/sample.rb") => [2, 4]
          }
        )
      end
    end
  end

  it "creates the output directory when needed" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        formatter = described_class.new(StringIO.new)
        notification = build_notification("spec/models/sample_spec.rb")

        allow(Coverage).to receive(:peek_result).and_return(
          coverage_snapshot(source_lines: [nil, 1, 0])
        )

        formatter.example_finished(notification)
        formatter.dump_summary(nil)

        expect(File).to exist("coverage/henitai_per_test.json")
      end
    end
  end

  it "writes the report under ENV-configured output dir" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        formatter = described_class.new(StringIO.new)
        notification = build_notification("spec/models/sample_spec.rb")
        reports_dir = File.join(dir, "custom-reports")

        with_env("HENITAI_REPORTS_DIR", reports_dir) do
          allow(Coverage).to receive(:peek_result).and_return(
            coverage_snapshot(source_lines: [nil, 1, 0])
          )

          formatter.example_finished(notification)
          formatter.dump_summary(nil)
        end

        expect(File).to exist(File.join(reports_dir, "henitai_per_test.json"))
      end
    end
  end

  it "does not write a report when coverage is unavailable" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        formatter = described_class.new(StringIO.new)
        notification = build_notification("spec/models/sample_spec.rb")

        allow(Coverage).to receive(:peek_result).and_raise(StandardError)

        formatter.example_finished(notification)
        formatter.dump_summary(nil)

        expect(File.exist?("coverage/henitai_per_test.json")).to be(false)
      end
    end
  end
end
