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

  describe "operator lists and reasons" do
    def write_two_operator_source(dir, directive)
      write_source(dir, <<~RUBY)
        class Sample
          def value(input)
            input * 2 #{directive}
          end
        end
      RUBY
    end

    def build_operator_mutant(file:, start_line:, operator:, subject_range: nil)
      mutant = build_mutant(file:, start_line:, subject_range:)
      mutant.instance_variable_set(:@operator, operator)
      mutant
    end

    it "restricts a trailing directive to the named operator" do
      Dir.mktmpdir do |dir|
        path = write_two_operator_source(dir, "# henitai:disable ArithmeticOperator")
        directives = described_class.new

        results = %w[ArithmeticOperator StringLiteral].map do |operator|
          directives.skip?(build_operator_mutant(file: path, start_line: 3, operator:))
        end

        expect(results).to eq([true, false])
      end
    end

    it "accepts a comma-separated operator list" do
      Dir.mktmpdir do |dir|
        path = write_two_operator_source(dir, "# henitai:disable ArithmeticOperator, StringLiteral")
        directives = described_class.new

        results = %w[ArithmeticOperator StringLiteral LogicalOperator].map do |operator|
          directives.skip?(build_operator_mutant(file: path, start_line: 3, operator:))
        end

        expect(results).to eq([true, true, false])
      end
    end

    it "captures a reason after an operator list" do
      Dir.mktmpdir do |dir|
        path = write_two_operator_source(dir, "# henitai:disable ArithmeticOperator: log-format noise")
        directive = described_class.new.directive_for(
          build_operator_mutant(file: path, start_line: 3, operator: "ArithmeticOperator")
        )

        expect([directive.reason, directive.operators.to_a]).to eq(
          ["log-format noise", ["ArithmeticOperator"]]
        )
      end
    end

    it "captures a reason without an operator list" do
      Dir.mktmpdir do |dir|
        path = write_two_operator_source(dir, "# henitai:disable: timing-sensitive")
        directive = described_class.new.directive_for(
          build_operator_mutant(file: path, start_line: 3, operator: "StringLiteral")
        )

        expect([directive.reason, directive.operators]).to eq(["timing-sensitive", nil])
      end
    end

    it "applies an operator list to a method-scoped directive" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            # henitai:disable RegexMutator: timing-sensitive matcher
            def value(input)
              input * 2
            end
          end
        RUBY
        directives = described_class.new

        results = %w[RegexMutator ArithmeticOperator].map do |operator|
          directives.skip?(
            build_operator_mutant(file: path, start_line: 4, operator:, subject_range: 3..5)
          )
        end

        expect(results).to eq([true, false])
      end
    end

    it "treats lowercase free-form rationale as a bare all-operator disable" do
      Dir.mktmpdir do |dir|
        path = write_two_operator_source(dir, "# henitai:disable reviewed defensive branch")

        expect(described_class.new.skip?(build_mutant(file: path, start_line: 3))).to be(true)
      end
    end

    it "raises for an unknown operator name with file and line" do
      Dir.mktmpdir do |dir|
        path = write_two_operator_source(dir, "# henitai:disable Bogus")

        expect do
          described_class.new.skip?(build_mutant(file: path, start_line: 3))
        end.to raise_error(
          Henitai::ConfigurationError,
          /#{Regexp.escape(path)}: unknown operator "Bogus" .*line 3.*henitai operator list/
        )
      end
    end
  end

  describe "regions" do
    def region_mutant(path, start_line, operator: "ArithmeticOperator")
      mutant = build_mutant(file: path, start_line:)
      mutant.instance_variable_set(:@operator, operator)
      mutant
    end

    it "covers every line between disable-start and disable-end" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            def value(input)
              input + 1
              # henitai:disable-start
              input + 2
              input + 3
              # henitai:disable-end
              input + 4
            end
          end
        RUBY
        directives = described_class.new

        results = [3, 5, 6, 8].map { |line| directives.skip?(region_mutant(path, line)) }

        expect(results).to eq([false, true, true, false])
      end
    end

    it "restricts a region to its named operators" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            def value(input)
              # henitai:disable-start ConditionalExpression
              input + 2
              # henitai:disable-end
            end
          end
        RUBY
        directives = described_class.new

        results = %w[ConditionalExpression ArithmeticOperator].map do |operator|
          directives.skip?(region_mutant(path, 4, operator:))
        end

        expect(results).to eq([true, false])
      end
    end

    it "raises for an unmatched disable-end" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            # henitai:disable-end
          end
        RUBY

        expect { described_class.new.skip?(build_mutant(file: path, start_line: 1)) }.to raise_error(
          Henitai::ConfigurationError,
          /#{Regexp.escape(path)}: `henitai:disable-end` without a matching start at line 2/
        )
      end
    end

    it "raises for an unclosed disable-start" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            # henitai:disable-start
          end
        RUBY

        expect { described_class.new.skip?(build_mutant(file: path, start_line: 1)) }.to raise_error(
          Henitai::ConfigurationError,
          /#{Regexp.escape(path)}: unclosed `henitai:disable-start` \(opened at line 2\)/
        )
      end
    end

    it "raises for a nested disable-start" do
      Dir.mktmpdir do |dir|
        path = write_source(dir, <<~RUBY)
          class Sample
            # henitai:disable-start
            # henitai:disable-start
            # henitai:disable-end
          end
        RUBY

        expect { described_class.new.skip?(build_mutant(file: path, start_line: 1)) }.to raise_error(
          Henitai::ConfigurationError,
          /#{Regexp.escape(path)}: nested `henitai:disable-start` at line 3/
        )
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
