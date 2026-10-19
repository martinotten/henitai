# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe Henitai::FlakyTestRegistry do
  describe ".for_config" do
    let(:reports_dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(reports_dir) }

    before do
      File.write(
        File.join(reports_dir, described_class::FILE_NAME),
        JSON.generate("flaky_tests" => ["spec/a_spec.rb"])
      )
    end

    it "loads the persisted set when flaky detection is enabled" do
      config = Struct.new(:flaky_detection, :reports_dir).new(true, reports_dir)

      expect(described_class.for_config(config).all).to eq([File.expand_path("spec/a_spec.rb")])
    end

    it "ignores a persisted set when flaky detection is disabled" do
      config = Struct.new(:flaky_detection, :reports_dir).new(false, reports_dir)

      expect(described_class.for_config(config).empty?).to be(true)
    end
  end

  describe ".from_outcomes" do
    it "marks a test file flaky when it passes in one run and fails in the other" do
      first = { "/app/a_spec.rb" => true, "/app/b_spec.rb" => true }
      second = { "/app/a_spec.rb" => false, "/app/b_spec.rb" => true }

      registry = described_class.from_outcomes(first, second)

      expect(registry.all).to eq(["/app/a_spec.rb"])
    end

    it "ignores files that behave the same in both runs" do
      outcomes = { "/app/a_spec.rb" => false }

      expect(described_class.from_outcomes(outcomes, outcomes).all).to be_empty
    end

    it "ignores files that appear in only one run" do
      registry = described_class.from_outcomes({ "/app/a_spec.rb" => true }, {})

      expect(registry.all).to be_empty
    end

    it "does not call a file flaky that failed in one run and is missing from the other" do
      registry = described_class.from_outcomes({ "/app/a_spec.rb" => "failed" }, { "/app/b_spec.rb" => "passed" })

      expect(registry.all).to be_empty
    end
  end

  describe ".load" do
    it "reads the flaky set written by #write" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "henitai_flaky_tests.json")
        described_class.new(["/app/a_spec.rb"]).write(path)

        expect(described_class.load(path).flaky?("/app/a_spec.rb")).to be(true)
      end
    end

    it "returns an empty registry when the file is missing" do
      Dir.mktmpdir do |dir|
        expect(described_class.load(File.join(dir, "missing.json")).all).to be_empty
      end
    end
  end

  describe "#write" do
    it "stores the flaky tests under the flaky_tests key" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "henitai_flaky_tests.json")
        described_class.new(["/app/a_spec.rb"]).write(path)

        expect(JSON.parse(File.read(path))).to eq("flaky_tests" => ["/app/a_spec.rb"])
      end
    end
  end

  describe "#flaky?" do
    it "is false for files outside the flaky set" do
      expect(described_class.new(["/app/a_spec.rb"]).flaky?("/app/b_spec.rb")).to be(false)
    end
  end
end
