# frozen_string_literal: true

require "fileutils"
require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::VerdictFingerprint do
  def build_mutant(source_file:, source_range:)
    subject = Struct.new(:source_file, :source_range).new(source_file, source_range)
    Struct.new(:subject).new(subject)
  end

  describe ".subject_source_hash" do
    it "hashes only the subject's source lines" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "sample.rb")
        File.write(path, "class Sample\n  def value = 1\nend\n")
        mutant = build_mutant(source_file: path, source_range: 2..2)

        hash_before = described_class.subject_source_hash(mutant)
        File.write(path, "# comment added above\nclass Sample\n  def value = 1\nend\n")
        hash_after = described_class.subject_source_hash(
          build_mutant(source_file: path, source_range: 3..3)
        )

        expect(hash_before).to eq(hash_after)
      end
    end

    it "changes when the subject's source changes" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "sample.rb")
        File.write(path, "class Sample\n  def value = 1\nend\n")
        mutant = build_mutant(source_file: path, source_range: 2..2)

        hash_before = described_class.subject_source_hash(mutant)
        File.write(path, "class Sample\n  def value = 2\nend\n")
        hash_after = described_class.subject_source_hash(mutant)

        expect(hash_before).not_to eq(hash_after)
      end
    end

    it "returns nil for an unreadable file" do
      mutant = build_mutant(source_file: "/no/such/file.rb", source_range: 1..1)

      expect(described_class.subject_source_hash(mutant)).to be_nil
    end

    it "returns nil when the subject has no source range" do
      mutant = build_mutant(source_file: "lib/sample.rb", source_range: nil)

      expect(described_class.subject_source_hash(mutant)).to be_nil
    end

    it "returns nil when subject has no source_file or source_range" do
      bare_subject = Struct.new.new
      mutant = Struct.new(:subject).new(bare_subject)

      expect(described_class.subject_source_hash(mutant)).to be_nil
    end
  end

  describe ".tests_fingerprint" do
    it "distinguishes different path and content boundaries" do
      allow(File).to receive(:read) do |path|
        {
          "ab" => "c",
          "a" => "bc",
          "d" => "e"
        }.fetch(path)
      end

      fingerprint_one = described_class.tests_fingerprint(%w[ab d])
      fingerprint_two = described_class.tests_fingerprint(%w[a d])

      expect(fingerprint_one).not_to eq(fingerprint_two)
    end

    it "round-trips as current while the test files are unchanged" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a_spec.rb")
        File.write(path, "it works\n")

        fingerprint = described_class.tests_fingerprint([path])

        expect(described_class.tests_fingerprint_current?(fingerprint)).to be(true)
      end
    end

    it "is no longer current after a test file changes" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a_spec.rb")
        File.write(path, "it works\n")
        fingerprint = described_class.tests_fingerprint([path])

        File.write(path, "it works differently\n")

        expect(described_class.tests_fingerprint_current?(fingerprint)).to be(false)
      end
    end

    it "is no longer current after a test file is deleted" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a_spec.rb")
        File.write(path, "it works\n")
        fingerprint = described_class.tests_fingerprint([path])

        File.delete(path)

        expect(described_class.tests_fingerprint_current?(fingerprint)).to be(false)
      end
    end

    it "returns nil for an empty test list without calling File.read" do
      allow(File).to receive(:read) { raise "unexpected File.read call" }
      expect(described_class.tests_fingerprint([])).to be_nil
    end

    it "returns nil when a test file is unreadable" do
      expect(described_class.tests_fingerprint(["/no/such/spec.rb"])).to be_nil
    end

    it "returns false for a valid fingerprint when files are modified" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a_spec.rb")
        File.write(path, "it works\n")

        fingerprint = described_class.tests_fingerprint([path])
        File.write(path, "modified\n")

        expect(described_class.tests_fingerprint_current?(fingerprint)).to be(false)
      end
    end

    it "detects separator collisions in combined content hash" do
      Dir.mktmpdir do |dir|
        path1 = File.join(dir, "a_spec.rb")
        path2 = File.join(dir, "b_spec.rb")
        File.write(path1, "x\n")
        File.write(path2, "y\n")

        # Two separate files produce a different hash than a single file
        # whose path+content concatenation would otherwise collide.
        fingerprint_two = described_class.tests_fingerprint([path1, path2])

        # A crafted single-path fingerprint that would collide if ":" were
        # absent from the digest input.
        fake_single_path = File.join(dir, "a_spec.rb")
        fake_content = "xy\n"
        File.write(fake_single_path, fake_content)

        # The two-file fingerprint must differ from any single-file variant.
        expect(described_class.tests_fingerprint([fake_single_path]))
          .not_to eq(fingerprint_two)
      end
    end

    it "returns false for malformed fingerprint JSON" do
      expect(described_class.tests_fingerprint_current?("not-json")).to be(false)
    end
  end

  describe ".dependency_fingerprint" do
    it "is stable while the dependency files are unchanged" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Gemfile.lock"), "GEM\n")

        first = described_class.dependency_fingerprint(dir)
        second = described_class.dependency_fingerprint(dir)

        expect(first).to eq(second)
      end
    end

    it "changes when a support file changes" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec", "support"))
        support = File.join(dir, "spec", "support", "factories.rb")
        File.write(support, "module Factories; end\n")

        before = described_class.dependency_fingerprint(dir)
        File.write(support, "module Factories; A = 1; end\n")

        expect(described_class.dependency_fingerprint(dir)).not_to eq(before)
      end
    end

    it "changes when a spec helper changes" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        helper = File.join(dir, "spec", "spec_helper.rb")
        File.write(helper, "require 'rspec'\n")

        before = described_class.dependency_fingerprint(dir)
        File.write(helper, "require 'rspec'\nSETTING = true\n")

        expect(described_class.dependency_fingerprint(dir)).not_to eq(before)
      end
    end

    it "ignores generated artifacts inside fixture projects", :aggregate_failures do
      Dir.mktmpdir do |dir|
        fixture = File.join(dir, "spec", "fixtures", "smoke")
        FileUtils.mkdir_p(File.join(fixture, "reports", "mutation-logs"))
        FileUtils.mkdir_p(File.join(fixture, "coverage"))
        # Project markers make reports/ and coverage/ recognizable as the
        # fixture project's own generated output directories.
        File.write(File.join(fixture, "Gemfile"), "source 'https://rubygems.org'\n")
        File.write(File.join(dir, "Gemfile.lock"), "GEM\n")

        before = described_class.dependency_fingerprint(dir)
        File.write(File.join(fixture, "reports", "mutation-logs", "mutant-1.log"), "churn")
        File.write(File.join(fixture, "coverage", ".resultset.json"), "{}")

        expect(described_class.dependency_fingerprint(dir)).to eq(before)
        expect(described_class.dependency_files(dir)).to eq(
          [File.join(dir, "Gemfile.lock"), File.join(fixture, "Gemfile")]
        )
      end
    end

    it "keeps legitimate support directories that share generated-artifact names" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec", "support", "coverage"))
        FileUtils.mkdir_p(File.join(dir, "spec", "factories", "reports"))
        helper = File.join(dir, "spec", "support", "coverage", "helper.rb")
        factory = File.join(dir, "spec", "factories", "reports", "factory.rb")
        File.write(helper, "module CoverageHelper; end\n")
        File.write(factory, "module ReportFactory; end\n")

        expect(described_class.dependency_files(dir)).to contain_exactly(helper, factory)
      end
    end

    it "invalidates when a legitimately named support file changes" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec", "support", "coverage"))
        helper = File.join(dir, "spec", "support", "coverage", "helper.rb")
        File.write(helper, "A = 1\n")

        before = described_class.dependency_fingerprint(dir)
        File.write(helper, "A = 2\n")

        expect(described_class.dependency_fingerprint(dir)).not_to eq(before)
      end
    end

    it "simply excludes missing dependency files instead of failing" do
      Dir.mktmpdir do |dir|
        expect(described_class.dependency_fingerprint(dir)).to be_a(String)
      end
    end
  end

  describe ".survivor_tests_fingerprint" do
    it "records the sorted covering paths, their content sha and the dependency sha" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a_spec.rb")
        File.write(path, "it works\n")

        fingerprint = described_class.survivor_tests_fingerprint([path], dependency_sha: "deps")
        parsed = JSON.parse(fingerprint)

        expect([parsed["paths"], parsed["dependencies"], parsed["sha"].nil?])
          .to eq([[path], "deps", false])
      end
    end

    it "returns nil for an empty covering set" do
      expect(described_class.survivor_tests_fingerprint([], dependency_sha: "deps")).to be_nil
    end

    it "returns nil without a dependency sha" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a_spec.rb")
        File.write(path, "it works\n")

        expect(described_class.survivor_tests_fingerprint([path], dependency_sha: nil)).to be_nil
      end
    end

    it "returns nil when a covering test file is unreadable" do
      expect(
        described_class.survivor_tests_fingerprint(["/no/such_spec.rb"], dependency_sha: "deps")
      ).to be_nil
    end
  end

  describe ".survivor_fingerprint_current?" do
    def recorded_fingerprint(paths, dependency_sha: "deps")
      Henitai::VerdictFingerprint.survivor_tests_fingerprint(paths, dependency_sha:)
    end

    it "is current when membership, contents and dependencies are unchanged" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a_spec.rb")
        File.write(path, "it works\n")
        fingerprint = recorded_fingerprint([path])

        expect(
          described_class.survivor_fingerprint_current?(
            fingerprint, live_paths: [path], dependency_sha: "deps"
          )
        ).to be(true)
      end
    end

    it "is stale when a new test now covers the mutant" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a_spec.rb")
        extra = File.join(dir, "b_spec.rb")
        File.write(path, "it works\n")
        File.write(extra, "it kills\n")
        fingerprint = recorded_fingerprint([path])

        expect(
          described_class.survivor_fingerprint_current?(
            fingerprint, live_paths: [path, extra], dependency_sha: "deps"
          )
        ).to be(false)
      end
    end

    it "is stale when a covering test dropped out of the live set" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a_spec.rb")
        gone = File.join(dir, "b_spec.rb")
        File.write(path, "it works\n")
        File.write(gone, "it worked\n")
        fingerprint = recorded_fingerprint([path, gone])

        expect(
          described_class.survivor_fingerprint_current?(
            fingerprint, live_paths: [path], dependency_sha: "deps"
          )
        ).to be(false)
      end
    end

    it "is stale when a covering test's content changed" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a_spec.rb")
        File.write(path, "it works\n")
        fingerprint = recorded_fingerprint([path])
        File.write(path, "it works differently\n")

        expect(
          described_class.survivor_fingerprint_current?(
            fingerprint, live_paths: [path], dependency_sha: "deps"
          )
        ).to be(false)
      end
    end

    it "is stale when the dependency fingerprint changed" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a_spec.rb")
        File.write(path, "it works\n")
        fingerprint = recorded_fingerprint([path])

        expect(
          described_class.survivor_fingerprint_current?(
            fingerprint, live_paths: [path], dependency_sha: "other-deps"
          )
        ).to be(false)
      end
    end

    it "treats a nil fingerprint or nil dependency sha as stale" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a_spec.rb")
        File.write(path, "it works\n")
        fingerprint = recorded_fingerprint([path])

        expect(
          [
            described_class.survivor_fingerprint_current?(
              nil, live_paths: [path], dependency_sha: "deps"
            ),
            described_class.survivor_fingerprint_current?(
              fingerprint, live_paths: [path], dependency_sha: nil
            )
          ]
        ).to eq([false, false])
      end
    end

    it "treats a killed-style fingerprint without dependency data as stale" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a_spec.rb")
        File.write(path, "it works\n")
        fingerprint = described_class.tests_fingerprint([path])

        expect(
          described_class.survivor_fingerprint_current?(
            fingerprint, live_paths: [path], dependency_sha: "deps"
          )
        ).to be(false)
      end
    end
  end
end
