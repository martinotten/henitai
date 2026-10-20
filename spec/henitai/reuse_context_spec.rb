# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::ReuseContext do
  def build_config(**overrides)
    defaults = {
      integration: "rspec", operators: :light, test_excludes: [],
      coverage_criteria: { test_result: true, timeout: true, process_abort: true }
    }
    Struct.new(*defaults.keys, keyword_init: true).new(**defaults, **overrides)
  end

  def fingerprint_in(dir, version: "1.0.0", **overrides)
    described_class.new(config: build_config(**overrides), version:, root: dir).fingerprint
  end

  it "is stable for identical inputs" do
    Dir.mktmpdir do |dir|
      first = fingerprint_in(dir)

      expect(fingerprint_in(dir)).to eq(first)
    end
  end

  it "computes the fingerprint once per instance" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "spec", "support"))
      helper = File.join(dir, "spec", "support", "helper.rb")
      File.write(helper, "A = 1\n")
      context = described_class.new(config: build_config, version: "1", root: dir)
      before = context.fingerprint
      File.write(helper, "A = 2\n")

      expect(context.fingerprint).to eq(before)
    end
  end

  it "changes when a spec/support helper changes" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "spec", "support"))
      helper = File.join(dir, "spec", "support", "helper.rb")
      File.write(helper, "A = 1\n")
      before = fingerprint_in(dir)
      File.write(helper, "A = 2\n")

      expect(fingerprint_in(dir)).not_to eq(before)
    end
  end

  it "changes with the henitai version" do
    Dir.mktmpdir do |dir|
      expect(fingerprint_in(dir, version: "2.0.0")).not_to eq(fingerprint_in(dir))
    end
  end

  {
    "operators" => { operators: :full },
    "test_excludes" => { test_excludes: ["spec/slow/**/*"] },
    "integration" => { integration: "minitest" },
    "coverage_criteria" => { coverage_criteria: { test_result: true, timeout: false, process_abort: true } }
  }.each do |name, override|
    it "changes with the #{name} setting" do
      Dir.mktmpdir do |dir|
        expect(fingerprint_in(dir, **override)).not_to eq(fingerprint_in(dir))
      end
    end
  end

  it "ignores the order of test_excludes and of coverage_criteria keys" do
    Dir.mktmpdir do |dir|
      first = fingerprint_in(dir, test_excludes: %w[a b], coverage_criteria: { timeout: true, test_result: true })
      second = fingerprint_in(dir, test_excludes: %w[b a], coverage_criteria: { test_result: true, timeout: true })

      expect(first).to eq(second)
    end
  end

  it "is nil when the dependency files cannot be read" do
    allow(Henitai::VerdictFingerprint).to receive(:dependency_fingerprint).and_return(nil)

    expect(described_class.new(config: build_config).fingerprint).to be_nil
  end
end
