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

  def write_report(dir, filename, data)
    coverage_dir = File.join(dir, "coverage")
    FileUtils.mkdir_p(coverage_dir)
    File.write(File.join(coverage_dir, filename), data.to_json)
  end

  def write_coverage_report(dir, data)
    write_report(dir, ".resultset.json", data)
  end

  def write_per_test_coverage_report(dir, data)
    write_report(dir, "henitai_per_test.json", data)
  end

  def with_sample_file(source, file_name: "sample.rb")
    Dir.mktmpdir do |dir|
      path = File.join(dir, file_name)
      File.write(path, source)
      yield dir, path
    end
  end

  def arithmetic_mutants(path, range: 1..4)
    subject = sample_subject(path, range:)

    Henitai::MutantGenerator.new.generate(
      [subject],
      [Henitai::Operators::ArithmeticOperator.new]
    )
  end

  def filter_with_coverage(**)
    filter = described_class.new(**)
    allow(filter).to receive(:coverage_lines_by_file).and_return("sample.rb" => [1])
    filter
  end

  def apply_mutants(dir, mutants, configuration = config, filter: described_class.new)
    Dir.chdir(dir) do
      filter.apply(mutants, configuration)
    end
  end

  def set_mutant_location(mutant, file:, start_line:, end_line:)
    mutant.location[:file] = file
    mutant.location[:start_line] = start_line
    mutant.location[:end_line] = end_line
  end

  def sample_subject(path, range: 1..4)
    Henitai::Subject.new(
      namespace: "Sample",
      method_name: "value",
      source_location: { file: path, range: range }
    )
  end

  it "marks mutants whose source matches an ignore pattern as ignored" do
    mutant = build_mutant("foo.bar")

    filter_with_coverage.apply([mutant], config(ignore_patterns: ["foo\\.bar"]))

    expect(mutant.status).to eq(:ignored)
  end

  it "marks mutants on a line with a trailing skip directive as ignored" do
    with_sample_file(<<~RUBY) do |dir, path|
      class Sample
        def value(input)
          input + 1 # henitai:disable
        end
      end
    RUBY

      mutants = arithmetic_mutants(path)
      apply_mutants(dir, mutants)

      expect(mutants.map(&:status).uniq).to eq([:ignored])
    end
  end

  it "marks every mutant of a method with a leading skip directive as ignored" do
    with_sample_file(<<~RUBY) do |dir, path|
      class Sample
        # henitai:disable
        def value(input)
          input + 1
        end
      end
    RUBY

      mutants = arithmetic_mutants(path, range: 3..5)
      apply_mutants(dir, mutants)

      expect(mutants.map(&:status).uniq).to eq([:ignored])
    end
  end

  it "leaves mutants on lines without a skip directive untouched" do
    with_sample_file(<<~RUBY) do |dir, path|
      class Sample
        def value(input)
          tagged = input + 1 # henitai:disable
          tagged + 2
        end
      end
    RUBY

      mutants = arithmetic_mutants(path)
      apply_mutants(dir, mutants)

      statuses = mutants.group_by { |mutant| mutant.location[:start_line] }
                        .transform_values { |group| group.map(&:status).uniq }
      expect(statuses.slice(3, 4)).to eq(3 => [:ignored], 4 => [:pending])
    end
  end

  it "prefers the skip directive over equivalence detection" do
    with_sample_file(<<~RUBY) do |dir, path|
      class Sample
        def value(input)
          input + 0 # henitai:disable
        end
      end
    RUBY

      mutant = arithmetic_mutants(path).find do |candidate|
        candidate.description == "replaced + with -"
      end

      apply_mutants(dir, [mutant])

      expect(mutant.status).to eq(:ignored)
    end
  end

  it "consults an injected skip-directives collaborator" do
    mutant = build_mutant("foo.bar")
    directive = Henitai::MutationSkipDirectives::Directive.new(operators: nil, reason: nil)
    skip_directives = instance_double(Henitai::MutationSkipDirectives, directive_for: directive)

    filter_with_coverage(skip_directives:).apply([mutant], config)

    expect(mutant.status).to eq(:ignored)
  end

  it "attaches the directive reason to the ignored mutant" do
    mutant = build_mutant("foo.bar")
    directive = Henitai::MutationSkipDirectives::Directive.new(operators: nil, reason: "log noise")
    skip_directives = instance_double(Henitai::MutationSkipDirectives, directive_for: directive)

    filter_with_coverage(skip_directives:).apply([mutant], config)

    expect(mutant.ignore_reason).to eq("log noise")
  end

  it "leaves mutants alone when no directive matches" do
    mutant = build_mutant("foo.bar")
    skip_directives = instance_double(Henitai::MutationSkipDirectives, directive_for: nil)

    filter_with_coverage(skip_directives:).apply([mutant], config)

    expect(mutant.status).not_to eq(:ignored)
  end

  it "marks arithmetic neutral mutants as equivalent" do
    with_sample_file(<<~RUBY) do |dir, path|
      class Sample
        def value(input)
          input + 0
        end
      end
    RUBY

      mutant = arithmetic_mutants(path).find do |candidate|
        candidate.description == "replaced + with -"
      end

      apply_mutants(dir, [mutant])

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

      set_mutant_location(
        mutant,
        file: File.expand_path("lib/sample.rb", dir),
        start_line: 4,
        end_line: 4
      )
      apply_mutants(dir, [mutant])

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

      set_mutant_location(
        mutant,
        file: File.join(dir, "lib", "sample.rb"),
        start_line: 3,
        end_line: 3
      )
      apply_mutants(dir, [mutant], config(reports_dir: coverage_dir))

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

      set_mutant_location(mutant, file: File.join(dir, "lib", "sample.rb"), start_line: 2, end_line: 2)
      apply_mutants(dir, [mutant], config(reports_dir: coverage_dir))

      expect(mutant.status).to eq(:no_coverage)
    end
  end

  it "leaves mutants pending when the coverage report is missing" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")
      set_mutant_location(mutant, file: "lib/sample.rb", start_line: 2, end_line: 2)
      apply_mutants(dir, [mutant])

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

      set_mutant_location(mutant, file: "lib/sample.rb", start_line: 2, end_line: 2)
      apply_mutants(dir, [mutant])

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

      set_mutant_location(mutant, file: File.join(dir, "sample.rb"), start_line: 3, end_line: 3)
      apply_mutants(dir, [mutant])

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

      set_mutant_location(mutant, file: File.join(dir, "sample.rb"), start_line: 2, end_line: 2)
      apply_mutants(dir, [mutant])

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

      set_mutant_location(mutant, file: File.join(dir, "sample.rb"), start_line: 1, end_line: 3)
      apply_mutants(dir, [mutant])

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

      set_mutant_location(mutant, file: File.join(dir, "sample.rb"), start_line: 3, end_line: 3)
      apply_mutants(dir, [mutant])

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

      set_mutant_location(mutant, file: File.join(dir, "sample.rb"), start_line: 2, end_line: 2)
      apply_mutants(dir, [mutant])

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

      set_mutant_location(mutant, file: File.join(dir, "sample.rb"), start_line: 2, end_line: 2)
      apply_mutants(dir, [mutant])

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

      set_mutant_location(mutant, file: File.join(dir, "sample.rb"), start_line: 3, end_line: 3)
      apply_mutants(dir, [mutant], config(ignore_patterns: ["foo\\.bar"]))

      expect(mutant.status).to eq(:ignored)
    end
  end

  it "keeps mutants that do not match any ignore pattern pending" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")

      apply_mutants(
        dir,
        [mutant],
        config(ignore_patterns: ["foo\\.baz"]),
        filter: filter_with_coverage
      )

      expect(mutant.status).to eq(:pending)
    end
  end

  it "treats a nil config as having no ignore patterns" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant("foo.bar")

      apply_mutants(dir, [mutant], nil, filter: filter_with_coverage)

      expect(mutant.status).to eq(:pending)
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

      apply_mutants(dir, [mutant], config(ignore_patterns: ["foo"]), filter: filter_with_coverage)

      expect(mutant.status).to eq(:pending)
    end
  end
end
