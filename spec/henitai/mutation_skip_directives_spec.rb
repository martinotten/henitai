# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Henitai::MutationSkipDirectives do
  def write_source(dir, source)
    path = File.join(dir, "sample.rb")
    File.write(path, source)
    path
  end

  def build_mutant(file:, start_line:, subject_range: nil)
    node = Henitai::SourceParser.parse("1 + 1")

    Henitai::Mutant.new(
      subject: Henitai::Subject.new(
        namespace: "Sample",
        method_name: "value",
        source_location: subject_range && { file:, range: subject_range }
      ),
      operator: "ArithmeticOperator",
      nodes: { original: node, mutated: node },
      description: "example mutation",
      location: { file:, start_line:, end_line: start_line, start_col: 0, end_col: 1 }
    )
  end

  describe "line-scoped directives" do
    it "skips mutants on a line with a trailing directive" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            def value(input)
              input * 2 # henitai:disable
            end
          end
        RUBY

        expect(described_class.new.skip?(build_mutant(file: path, start_line: 3))).to be(true)
      end
    end

    it "does not skip mutants on other lines" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            def value(input)
              input * 2 # henitai:disable
            end
          end
        RUBY

        expect(described_class.new.skip?(build_mutant(file: path, start_line: 2))).to be(false)
      end
    end

    it "treats a trailing directive on the def line as line-scoped only" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            def value(input = 1) # henitai:disable
              input * 2
            end
          end
        RUBY

        directives = described_class.new
        results = [
          directives.skip?(build_mutant(file: path, start_line: 2, subject_range: 2..4)),
          directives.skip?(build_mutant(file: path, start_line: 3, subject_range: 2..4))
        ]

        expect(results).to eq([true, false])
      end
    end

    it "recognizes a directive followed by explanatory text" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            def value(input)
              input * 2 # henitai:disable -- reviewed defensive branch
            end
          end
        RUBY

        expect(described_class.new.skip?(build_mutant(file: path, start_line: 3))).to be(true)
      end
    end

    it "does not recognize a directive with a different suffix or case" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            def value(input)
              input * 2 # henitai:disabled
              input * 3 # HENITAI:DISABLE
            end
          end
        RUBY

        directives = described_class.new
        results = [
          directives.skip?(build_mutant(file: path, start_line: 3)),
          directives.skip?(build_mutant(file: path, start_line: 4))
        ]

        expect(results).to eq([false, false])
      end
    end
  end

  describe "method-scoped directives" do
    it "skips every mutant of a subject whose def has a directive directly above it" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            # henitai:disable
            def value(input)
              input * 2
            end
          end
        RUBY

        expect(described_class.new.skip?(build_mutant(file: path, start_line: 4, subject_range: 3..5))).to be(true)
      end
    end

    it "skips when the directive sits within a contiguous comment block above the def" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            # henitai:disable
            # Doubles the input.
            def value(input)
              input * 2
            end
          end
        RUBY

        expect(described_class.new.skip?(build_mutant(file: path, start_line: 5, subject_range: 4..6))).to be(true)
      end
    end

    it "does not skip when a blank line separates the directive from the def" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            # henitai:disable

            def value(input)
              input * 2
            end
          end
        RUBY

        expect(described_class.new.skip?(build_mutant(file: path, start_line: 5, subject_range: 4..6))).to be(false)
      end
    end

    it "does not skip when the subject has no source range" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            # henitai:disable
            def value(input)
              input * 2
            end
          end
        RUBY

        expect(described_class.new.skip?(build_mutant(file: path, start_line: 4))).to be(false)
      end
    end
  end

  describe "robustness" do
    it "returns false for a nonexistent file without raising" do
      expect(described_class.new.skip?(build_mutant(file: "/no/such/file.rb", start_line: 1))).to be(false)
    end

    it "returns false for a file without comments" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            def value(input)
              input * 2
            end
          end
        RUBY

        expect(described_class.new.skip?(build_mutant(file: path, start_line: 3))).to be(false)
      end
    end
  end

  describe "caching" do
    it "parses each file only once across repeated lookups" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            def value(input)
              input * 2 # henitai:disable
            end
          end
        RUBY

        first = build_mutant(file: path, start_line: 3)
        second = build_mutant(file: path, start_line: 2)
        directives = described_class.new
        allow(Prism).to receive(:parse).and_call_original

        directives.skip?(first)
        directives.skip?(second)

        expect(Prism).to have_received(:parse).once
      end
    end

    it "re-parses when the file mtime changes" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            def value(input)
              input * 2
            end
          end
        RUBY

        directives = described_class.new
        before_change = directives.skip?(build_mutant(file: path, start_line: 3))

        File.write(path, <<~RUBY)
          class Sample
            def value(input)
              input * 2 # henitai:disable
            end
          end
        RUBY
        FileUtils.touch(path, mtime: File.mtime(path) + 10)
        after_change = directives.skip?(build_mutant(file: path, start_line: 3))

        expect([before_change, after_change]).to eq([false, true])
      end
    end
  end
end
