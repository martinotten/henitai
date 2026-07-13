# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::GeneratedArtifacts do
  def dir_with(name, entries, base)
    dir = File.join(base, name)
    FileUtils.mkdir_p(dir)
    entries.each do |entry|
      entry.end_with?("/") ? FileUtils.mkdir_p(File.join(dir, entry)) : File.write(File.join(dir, entry), "")
    end
    dir
  end

  describe ".generated_dir?" do
    it "recognizes SimpleCov output in a coverage directory" do
      Dir.mktmpdir do |base|
        expect(described_class.generated_dir?(dir_with("coverage", %w[.resultset.json], base))).to be(true)
      end
    end

    it "keeps a coverage directory holding only helpers" do
      Dir.mktmpdir do |base|
        expect(described_class.generated_dir?(dir_with("coverage", %w[helper.rb], base))).to be(false)
      end
    end

    it "recognizes a henitai reports directory by its artifacts" do
      Dir.mktmpdir do |base|
        expect(described_class.generated_dir?(dir_with("reports", %w[mutation-report.json], base))).to be(true)
      end
    end

    it "keeps a reports directory holding only fixture input" do
      Dir.mktmpdir do |base|
        expect(described_class.generated_dir?(dir_with("reports", %w[template.yml], base))).to be(false)
      end
    end

    it "recognizes a mutation-logs directory by per-mutant entries" do
      Dir.mktmpdir do |base|
        expect(described_class.generated_dir?(dir_with("mutation-logs", %w[mutant-1.log], base))).to be(true)
      end
    end

    it "treats an empty mutation-logs directory as evidence-free" do
      Dir.mktmpdir do |base|
        expect(described_class.generated_dir?(dir_with("mutation-logs", [], base))).to be(false)
      end
    end

    it "keeps a mutation-logs directory holding only unrelated entries" do
      Dir.mktmpdir do |base|
        expect(described_class.generated_dir?(dir_with("mutation-logs", %w[notes.txt], base))).to be(false)
      end
    end

    it "never flags directories with unrelated names" do
      Dir.mktmpdir do |base|
        expect(described_class.generated_dir?(dir_with("support", %w[.resultset.json], base))).to be(false)
      end
    end

    it "treats an unreadable directory as evidence-free" do
      expect(described_class.generated_dir?("/nonexistent/coverage")).to be(false)
    end
  end
end
