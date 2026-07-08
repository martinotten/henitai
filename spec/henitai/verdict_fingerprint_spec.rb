# frozen_string_literal: true

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

    it "returns nil for an empty test list" do
      expect(described_class.tests_fingerprint([])).to be_nil
    end

    it "returns nil when a test file is unreadable" do
      expect(described_class.tests_fingerprint(["/no/such/spec.rb"])).to be_nil
    end

    it "treats a nil fingerprint as not current" do
      expect(described_class.tests_fingerprint_current?(nil)).to be(false)
    end
  end
end
