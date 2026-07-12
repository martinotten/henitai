# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::PerTestCoverage do
  def build_mutant(file, start_line: 2, end_line: 2)
    Struct.new(:location).new(
      {
        file:,
        start_line:,
        end_line:
      }
    )
  end

  def write_report(dir, entries)
    File.write(
      File.join(dir, "henitai_per_test.json"),
      JSON.generate(entries)
    )
  end

  describe "#tests_covering" do
    it "returns the sorted test paths whose covered lines intersect the mutant" do
      Dir.mktmpdir do |dir|
        file = File.expand_path("lib/sample.rb")
        write_report(
          dir,
          "spec/z_spec.rb" => { file => [2] },
          "spec/a_spec.rb" => { file => [1, 2] },
          "spec/other_spec.rb" => { file => [9] }
        )

        coverage = described_class.new(reports_dir: dir)

        expect(coverage.tests_covering(build_mutant(file))).to eq(
          ["spec/a_spec.rb", "spec/z_spec.rb"]
        )
      end
    end

    it "excludes tests that only cover other source files" do
      Dir.mktmpdir do |dir|
        file = File.expand_path("lib/sample.rb")
        other = File.expand_path("lib/other.rb")
        write_report(dir, "spec/other_spec.rb" => { other => [2] })

        coverage = described_class.new(reports_dir: dir)

        expect(coverage.tests_covering(build_mutant(file))).to eq([])
      end
    end

    it "resolves against the mutant's current location after line drift" do
      Dir.mktmpdir do |dir|
        file = File.expand_path("lib/sample.rb")
        write_report(dir, "spec/a_spec.rb" => { file => [5] })

        coverage = described_class.new(reports_dir: dir)

        expect(coverage.tests_covering(build_mutant(file, start_line: 4, end_line: 6)))
          .to eq(["spec/a_spec.rb"])
      end
    end

    it "returns an empty set when the per-test report is missing" do
      Dir.mktmpdir do |dir|
        coverage = described_class.new(reports_dir: dir)

        expect(coverage.tests_covering(build_mutant(File.expand_path("lib/sample.rb")))).to eq([])
      end
    end

    it "returns an empty set when the mutant has no usable location" do
      Dir.mktmpdir do |dir|
        file = File.expand_path("lib/sample.rb")
        write_report(dir, "spec/a_spec.rb" => { file => [2] })
        mutant = Struct.new(:location).new({ file: })

        coverage = described_class.new(reports_dir: dir)

        expect(coverage.tests_covering(mutant)).to eq([])
      end
    end
  end

  describe "#covers?" do
    it "is true only for tests intersecting the mutant's line range" do
      Dir.mktmpdir do |dir|
        file = File.expand_path("lib/sample.rb")
        write_report(
          dir,
          "spec/a_spec.rb" => { file => [2] },
          "spec/b_spec.rb" => { file => [9] }
        )

        coverage = described_class.new(reports_dir: dir)
        mutant = build_mutant(file)

        expect(
          [coverage.covers?("spec/a_spec.rb", mutant), coverage.covers?("spec/b_spec.rb", mutant)]
        ).to eq([true, false])
      end
    end
  end

  describe "#available?" do
    it "reflects whether the per-test map holds any entries" do
      Dir.mktmpdir do |dir|
        empty = described_class.new(reports_dir: dir).available?
        write_report(dir, "spec/a_spec.rb" => { File.expand_path("lib/sample.rb") => [2] })
        populated = described_class.new(reports_dir: dir).available?

        expect([empty, populated]).to eq([false, true])
      end
    end
  end
end
