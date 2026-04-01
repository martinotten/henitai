# frozen_string_literal: true

require "json"
require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Henitai::StaticFilter do
  def build_mutant(source)
    node = Henitai::SourceParser.parse(source)

    Henitai::Mutant.new(
      subject: Henitai::Subject.new(namespace: "Example", method_name: "example"),
      operator: "ArithmeticOperator",
      nodes: { original: node, mutated: node },
      description: "example mutation",
      location: {
        file: "sample.rb",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 1
      }
    )
  end

  def config(ignore_patterns: [])
    Struct.new(:ignore_patterns).new(ignore_patterns)
  end

  def write_coverage_report(dir, data)
    coverage_dir = File.join(dir, "coverage")
    FileUtils.mkdir_p(coverage_dir)
    File.write(File.join(coverage_dir, ".resultset.json"), data.to_json)
  end

  def filter_with_coverage
    filter = described_class.new
    allow(filter).to receive(:coverage_lines_by_file).and_return("sample.rb" => [1])
    filter
  end

  it "marks mutants whose source matches an ignore pattern as ignored" do
    mutant = build_mutant("foo.bar")

    filter_with_coverage.apply([mutant], config(ignore_patterns: ["foo\\.bar"]))

    expect(mutant.status).to eq(:ignored)
  end

  it "caches compiled ignore patterns across repeated applications" do
    mutant = build_mutant("foo.bar")
    filter = filter_with_coverage

    allow(Regexp).to receive(:new).and_call_original

    filter.apply([mutant], config(ignore_patterns: ["foo\\.bar"]))
    filter.apply([mutant], config(ignore_patterns: ["foo\\.bar"]))

    expect(Regexp).to have_received(:new).once
  end

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

  it "returns an empty coverage map when the report is missing" do
    expect(described_class.new.coverage_lines_by_file("/tmp/missing-resultset.json")).to eq({})
  end

  it "marks uncovered mutants as no_coverage" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")
      write_coverage_report(
        dir,
        {
          "RSpec" => {
            "coverage" => {
              File.join(dir, "sample.rb") => {
                "lines" => [nil, 1, nil]
              }
            }
          }
        }
      )

      mutant.location[:file] = File.join(dir, "sample.rb")
      mutant.location[:start_line] = 3

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config)
      end

      expect(mutant.status).to eq(:no_coverage)
    end
  end

  it "keeps covered mutants pending" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")
      write_coverage_report(
        dir,
        {
          "RSpec" => {
            "coverage" => {
              File.join(dir, "sample.rb") => {
                "lines" => [nil, 1, nil]
              }
            }
          }
        }
      )

      mutant.location[:file] = File.join(dir, "sample.rb")
      mutant.location[:start_line] = 2

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config)
      end

      expect(mutant.status).to eq(:pending)
    end
  end

  it "keeps ignored mutants ignored even when they are uncovered" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")
      write_coverage_report(
        dir,
        {
          "RSpec" => {
            "coverage" => {
              File.join(dir, "sample.rb") => {
                "lines" => [nil, 1, nil]
              }
            }
          }
        }
      )

      mutant.location[:file] = File.join(dir, "sample.rb")
      mutant.location[:start_line] = 3

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config(ignore_patterns: ["foo\\.bar"]))
      end

      expect(mutant.status).to eq(:ignored)
    end
  end

  it "keeps mutants that do not match any ignore pattern pending" do
    mutant = build_mutant("foo.bar")

    filter_with_coverage.apply([mutant], config(ignore_patterns: ["foo\\.baz"]))

    expect(mutant.status).to eq(:pending)
  end

  it "treats a nil config as having no ignore patterns" do
    mutant = build_mutant("foo.bar")

    filter_with_coverage.apply([mutant], nil)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps mutants without source metadata pending" do
    mutant = Henitai::Mutant.new(
      subject: Henitai::Subject.new(namespace: "Example", method_name: "example"),
      operator: "ArithmeticOperator",
      nodes: {
        original: Struct.new(:location).new(Struct.new(:expression).new(nil)),
        mutated: Struct.new(:location).new(Struct.new(:expression).new(nil))
      },
      description: "example mutation",
      location: {
        file: "sample.rb",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 1
      }
    )

    filter_with_coverage.apply([mutant], config(ignore_patterns: ["foo"]))

    expect(mutant.status).to eq(:pending)
  end
end
