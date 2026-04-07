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

  def config(ignore_patterns: [], reports_dir: nil)
    Struct.new(:ignore_patterns, :reports_dir).new(ignore_patterns, reports_dir)
  end

  def write_coverage_report(dir, data)
    coverage_dir = File.join(dir, "coverage")
    FileUtils.mkdir_p(coverage_dir)
    File.write(File.join(coverage_dir, ".resultset.json"), data.to_json)
  end

  def write_per_test_coverage_report(dir, data)
    coverage_dir = File.join(dir, "coverage")
    FileUtils.mkdir_p(coverage_dir)
    File.write(File.join(coverage_dir, "henitai_per_test.json"), data.to_json)
  end

  def filter_with_coverage
    filter = described_class.new
    allow(filter).to receive(:coverage_lines_by_file).and_return("sample.rb" => [1])
    filter
  end

  def sample_subject(path)
    Henitai::Subject.new(namespace: "Sample", method_name: "value", source_location: { file: path, range: 1..4 })
  end

  it "marks mutants whose source matches an ignore pattern as ignored" do
    mutant = build_mutant("foo.bar")

    filter_with_coverage.apply([mutant], config(ignore_patterns: ["foo\\.bar"]))

    expect(mutant.status).to eq(:ignored)
  end

  it "marks arithmetic neutral mutants as equivalent" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(
        path,
        <<~RUBY
          class Sample
            def value(input)
              input + 0
            end
          end
        RUBY
      )

      subject = sample_subject(path)
      mutant = Henitai::MutantGenerator.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new]
      ).find { |candidate| candidate.description == "replaced + with -" }

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config)
      end

      expect(mutant.status).to eq(:equivalent)
    end
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

  it "normalizes coverage file paths when building the coverage map" do
    Dir.mktmpdir do |dir|
      report_path = File.join(dir, "coverage", ".resultset.json")
      FileUtils.mkdir_p(File.dirname(report_path))
      File.write(
        report_path,
        {
          "RSpec" => {
            "coverage" => {
              "lib/sample.rb" => {
                "lines" => [nil, 1]
              }
            }
          }
        }.to_json
      )

      Dir.chdir(dir) do
        coverage = described_class.new.coverage_lines_by_file(report_path)

        expect(coverage).to eq(
          File.expand_path("lib/sample.rb") => [2]
        )
      end
    end
  end

  it "builds a per-test coverage map from the formatter output" do
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

  it "returns an empty per-test coverage map when the report is missing" do
    expect(described_class.new.test_lines_by_file("/tmp/missing-per-test.json")).to eq({})
  end

  it "uses per-test coverage as a fallback when the global report is missing" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")
      per_test_path = File.join(dir, "coverage", "henitai_per_test.json")
      FileUtils.mkdir_p(File.dirname(per_test_path))
      File.write(
        per_test_path,
        {
          File.expand_path("spec/sample_spec.rb", dir) => {
            File.expand_path("lib/sample.rb", dir) => [2, 4]
          }
        }.to_json
      )

      mutant.location[:file] = File.expand_path("lib/sample.rb", dir)
      mutant.location[:start_line] = 4
      mutant.location[:end_line] = 4

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config)
      end

      expect(mutant.status).to eq(:pending)
    end
  end

  it "uses the configured reports dir for the SimpleCov resultset" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")
      coverage_dir = File.join(dir, "artifacts")
      FileUtils.mkdir_p(File.join(coverage_dir, "coverage"))
      File.write(
        File.join(coverage_dir, "coverage", ".resultset.json"),
        {
          "RSpec" => {
            "coverage" => {
              File.join(dir, "lib", "sample.rb") => {
                "lines" => [nil, 1, nil]
              }
            }
          }
        }.to_json
      )

      mutant.location[:file] = File.join(dir, "lib", "sample.rb")
      mutant.location[:start_line] = 3
      mutant.location[:end_line] = 3

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config(reports_dir: coverage_dir))
      end

      expect(mutant.status).to eq(:no_coverage)
    end
  end

  it "uses the configured reports dir for per-test coverage reports" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")
      coverage_dir = File.join(dir, "artifacts")
      FileUtils.mkdir_p(coverage_dir)
      File.write(
        File.join(coverage_dir, "henitai_per_test.json"),
        {
          "spec/models/sample_spec.rb" => {
            File.join(dir, "lib", "sample.rb") => [1]
          }
        }.to_json
      )

      mutant.location[:file] = File.join(dir, "lib", "sample.rb")
      mutant.location[:start_line] = 2
      mutant.location[:end_line] = 2

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config(reports_dir: coverage_dir))
      end

      expect(mutant.status).to eq(:no_coverage)
    end
  end

  it "leaves mutants pending when the coverage report is missing" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")
      mutant.location[:file] = "lib/sample.rb"
      mutant.location[:start_line] = 2
      mutant.location[:end_line] = 2

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config)
      end

      expect(mutant.status).to eq(:pending)
    end
  end

  it "matches covered mutants when coverage and mutant paths differ in form" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")
      FileUtils.mkdir_p(File.join(dir, "coverage"))
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib", "sample.rb"), "first\nsecond\n")
      File.write(
        File.join(dir, "coverage", ".resultset.json"),
        {
          "RSpec" => {
            "coverage" => {
              File.expand_path("lib/sample.rb", dir) => {
                "lines" => [nil, 1]
              }
            }
          }
        }.to_json
      )

      mutant.location[:file] = "lib/sample.rb"
      mutant.location[:start_line] = 2
      mutant.location[:end_line] = 2

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config)
      end

      expect(mutant.status).to eq(:pending)
    end
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
      mutant.location[:end_line] = 3

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
      mutant.location[:end_line] = 2

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config)
      end

      expect(mutant.status).to eq(:pending)
    end
  end

  it "keeps covered mutants pending when only an interior line of the range is covered" do
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
      mutant.location[:start_line] = 1
      mutant.location[:end_line] = 3

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config)
      end

      expect(mutant.status).to eq(:pending)
    end
  end

  it "uses per-test coverage data when the resultset report is absent" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")
      write_per_test_coverage_report(
        dir,
        {
          "spec/models/sample_spec.rb" => {
            File.join(dir, "sample.rb") => [1, 3]
          }
        }
      )

      mutant.location[:file] = File.join(dir, "sample.rb")
      mutant.location[:start_line] = 3
      mutant.location[:end_line] = 3

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config)
      end

      expect(mutant.status).to eq(:pending)
    end
  end

  it "treats mutant lines as covered when the enclosing method has a positive call count" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")
      write_coverage_report(
        dir,
        {
          "RSpec" => {
            "coverage" => {
              File.join(dir, "sample.rb") => {
                "lines" => [1, nil, nil],
                "methods" => {
                  "[Example, :example, 1, 0, 3, 3]" => 5
                }
              }
            }
          }
        }
      )

      mutant.location[:file]       = File.join(dir, "sample.rb")
      mutant.location[:start_line] = 2
      mutant.location[:end_line]   = 2

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config)
      end

      expect(mutant.status).to eq(:pending)
    end
  end

  it "does not cover mutant lines when the enclosing method has a zero call count" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")
      write_coverage_report(
        dir,
        {
          "RSpec" => {
            "coverage" => {
              File.join(dir, "sample.rb") => {
                "lines" => [nil, nil, nil],
                "methods" => {
                  "[Example, :example, 1, 0, 3, 3]" => 0
                }
              }
            }
          }
        }
      )

      mutant.location[:file]       = File.join(dir, "sample.rb")
      mutant.location[:start_line] = 2
      mutant.location[:end_line]   = 2

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config)
      end

      expect(mutant.status).to eq(:no_coverage)
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
      mutant.location[:end_line] = 3

      Dir.chdir(dir) do
        described_class.new.apply([mutant], config(ignore_patterns: ["foo\\.bar"]))
      end

      expect(mutant.status).to eq(:ignored)
    end
  end

  it "keeps mutants that do not match any ignore pattern pending" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")

      Dir.chdir(dir) do
        filter_with_coverage.apply([mutant], config(ignore_patterns: ["foo\\.baz"]))
      end

      expect(mutant.status).to eq(:pending)
    end
  end

  it "treats a nil config as having no ignore patterns" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")

      Dir.chdir(dir) do
        filter_with_coverage.apply([mutant], nil)
      end

      expect(mutant.status).to eq(:pending)
    end
  end

  describe "#normalize_path caching" do
    it "resolves each unique path only once per StaticFilter instance" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "sample.rb")
        FileUtils.touch(path)

        filter = described_class.new

        expect(File).to receive(:realpath).once.and_call_original
        2.times { filter.send(:normalize_path, path) }
      end
    end

    it "resolves different paths independently" do
      Dir.mktmpdir do |dir|
        path_a = File.join(dir, "a.rb")
        path_b = File.join(dir, "b.rb")
        FileUtils.touch(path_a)
        FileUtils.touch(path_b)

        filter = described_class.new

        expect(File).to receive(:realpath).twice.and_call_original
        filter.send(:normalize_path, path_a)
        filter.send(:normalize_path, path_b)
      end
    end

    it "falls back to the expanded path when the file does not exist" do
      filter = described_class.new
      result = filter.send(:normalize_path, "/no/such/file.rb")

      expect(result).to eq(File.expand_path("/no/such/file.rb"))
    end

    it "caches the fallback result for non-existent paths" do
      filter = described_class.new
      path = "/no/such/file.rb"

      filter.send(:normalize_path, path)

      expect(File).not_to receive(:realpath)
      filter.send(:normalize_path, path)
    end
  end

  it "keeps mutants without source metadata pending" do
    Dir.mktmpdir do |dir|
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

      Dir.chdir(dir) do
        filter_with_coverage.apply([mutant], config(ignore_patterns: ["foo"]))
      end

      expect(mutant.status).to eq(:pending)
    end
  end
end
