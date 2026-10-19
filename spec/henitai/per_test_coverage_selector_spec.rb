# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::PerTestCoverageSelector do
  let(:source) { File.expand_path("lib/sample.rb") }
  let(:selector) { described_class.new }

  def build_mutant(file, start_line: 2, end_line: 2)
    Struct.new(:location).new({ file:, start_line:, end_line: })
  end

  def write_report(dir, report)
    File.write(File.join(dir, "henitai_per_test.json"), JSON.generate(report))
  end

  # Records which lambda was consulted so specs can assert who decided.
  def select_for(mutant, dir, tests:, fallback: [])
    calls = []
    result = selector.select(
      mutant,
      reports_dir: dir,
      test_files: lambda {
        calls << :test_files
        tests
      },
      fallback: lambda {
        calls << :fallback
        fallback
      }
    )
    [result, calls]
  end

  it "selects the covering test that name matching would not have found (EXE-12)", :aggregate_failures do
    Dir.mktmpdir do |dir|
      write_report(dir, "spec/cart_spec.rb" => { source => [2] })

      result, calls = select_for(
        build_mutant(source),
        dir,
        tests: ["spec/tax_spec.rb", "spec/cart_spec.rb"],
        fallback: ["spec/tax_spec.rb"]
      )

      expect(result).to eq(["spec/cart_spec.rb"])
      expect(calls).not_to include(:fallback)
    end
  end

  it "adds name-matched tests for a mutant on the def line (load-time coverage)", :aggregate_failures do
    Dir.mktmpdir do |dir|
      write_report(dir, "spec/cart_spec.rb" => { source => [2] })
      subject = Struct.new(:source_range).new(2..4)
      mutant = Struct.new(:location, :subject).new({ file: source, start_line: 2, end_line: 2 }, subject)

      result, = select_for(
        mutant,
        dir,
        tests: ["spec/pricing_spec.rb", "spec/cart_spec.rb"],
        fallback: ["spec/pricing_spec.rb"]
      )

      expect(result).to contain_exactly("spec/cart_spec.rb", "spec/pricing_spec.rb")
    end
  end

  it "drops a name-matched test whose coverage misses the mutant when another test covers it" do
    Dir.mktmpdir do |dir|
      write_report(
        dir,
        "spec/tax_spec.rb" => { source => [4] },
        "spec/cart_spec.rb" => { source => [2] }
      )

      result, = select_for(
        build_mutant(source),
        dir,
        tests: ["spec/tax_spec.rb", "spec/cart_spec.rb"],
        fallback: ["spec/tax_spec.rb"]
      )

      expect(result).to eq(["spec/cart_spec.rb"])
    end
  end

  it "returns the integration's own path form for map keys written as ./relative paths" do
    Dir.mktmpdir do |dir|
      write_report(dir, "./spec/a_spec.rb" => { source => [2] })

      result, = select_for(build_mutant(source), dir, tests: ["spec/a_spec.rb", "spec/b_spec.rb"])

      expect(result).to eq(["spec/a_spec.rb"])
    end
  end

  it "drops a covering test that the integration no longer provides" do
    Dir.mktmpdir do |dir|
      write_report(
        dir,
        "spec/deleted_spec.rb" => { source => [2] },
        "spec/a_spec.rb" => { source => [2] }
      )

      result, = select_for(build_mutant(source), dir, tests: ["spec/a_spec.rb"])

      expect(result).to eq(["spec/a_spec.rb"])
    end
  end

  it "falls back to name matching when every covering test has been removed", :aggregate_failures do
    Dir.mktmpdir do |dir|
      write_report(dir, "spec/deleted_spec.rb" => { source => [2] })

      result, calls = select_for(
        build_mutant(source),
        dir,
        tests: ["spec/other_spec.rb"],
        fallback: ["spec/other_spec.rb"]
      )

      expect(result).to eq(["spec/other_spec.rb"])
      expect(calls).to include(:fallback)
    end
  end

  it "falls back to name matching when no test in the map covers the mutant", :aggregate_failures do
    Dir.mktmpdir do |dir|
      write_report(dir, "spec/tax_spec.rb" => { source => [40] })

      result, calls = select_for(
        build_mutant(source),
        dir,
        tests: ["spec/tax_spec.rb", "spec/cart_spec.rb"],
        fallback: ["spec/cart_spec.rb"]
      )

      expect(result).to eq(["spec/cart_spec.rb"])
      expect(calls).to include(:fallback)
    end
  end

  it "falls back without reading integration test files when no per-test report exists", :aggregate_failures do
    Dir.mktmpdir do |dir|
      result, calls = select_for(
        build_mutant(source),
        dir,
        tests: ["spec/tax_spec.rb"],
        fallback: ["spec/tax_spec.rb", "spec/cart_spec.rb"]
      )

      expect(result).to eq(["spec/tax_spec.rb", "spec/cart_spec.rb"])
      expect(calls).to eq([:fallback])
    end
  end

  it "falls back when the mutant location is incomplete", :aggregate_failures do
    Dir.mktmpdir do |dir|
      write_report(dir, "spec/a_spec.rb" => { source => [2] })

      result, calls = select_for(
        build_mutant(nil),
        dir,
        tests: ["spec/a_spec.rb"],
        fallback: ["spec/a_spec.rb", "spec/b_spec.rb"]
      )

      expect(result).to eq(["spec/a_spec.rb", "spec/b_spec.rb"])
      expect(calls).to eq([:fallback])
    end
  end

  it "keeps the integration order of the covering tests" do
    Dir.mktmpdir do |dir|
      write_report(
        dir,
        "spec/a_spec.rb" => { source => [2] },
        "spec/c_spec.rb" => { source => [3] }
      )

      result, = select_for(
        build_mutant(source, start_line: 2, end_line: 3),
        dir,
        tests: ["spec/c_spec.rb", "spec/b_spec.rb", "spec/a_spec.rb"]
      )

      expect(result).to eq(["spec/c_spec.rb", "spec/a_spec.rb"])
    end
  end
end
