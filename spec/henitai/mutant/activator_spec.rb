# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Mutant::Activator do
  def write_source(dir, source)
    path = File.join(dir, "sample.rb")
    File.write(path, source)
    path
  end

  def location_for(node)
    expression = node.location.expression
    {
      file: expression.source_buffer.name,
      start_line: expression.line,
      end_line: expression.last_line,
      start_col: expression.column,
      end_col: expression.last_column
    }
  end

  def build_mutant(subject:, original_node:, mutated_node:, location:)
    Henitai::Mutant.new(
      subject:,
      operator: "FakeOperator",
      nodes: {
        original: original_node,
        mutated: mutated_node
      },
      description: "replace node",
      location:
    )
  end

  it "patches an instance method" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class Sample
          def value
            1
          end
        end
      RUBY

      stub_const("Sample", Class.new)

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(Sample.new.value).to eq(2)
    end
  end

  it "patches a class method" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class Sample
          def self.value
            1
          end
        end
      RUBY

      stub_const("Sample", Class.new)

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).find do |candidate|
        candidate.expression == "Sample.value"
      end
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(Sample.value).to eq(2)
    end
  end

  it "loads an unloaded target constant before patching" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class Gate4TransientSample
          def value
            1
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(Gate4TransientSample.new.value).to eq(2)
    end
  end

  it "patches the full method body for nested mutations" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class Gate4NestedSample
          def wrap(value)
            value * 10
          end

          def value
            wrap(1 + 2)
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).find do |candidate|
        candidate.expression == "Gate4NestedSample#value"
      end
      mutant = Henitai::MutantGenerator.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new]
      ).first

      described_class.activate!(mutant)

      expect(Gate4NestedSample.new.value).to eq(-10)
    end
  end

  it "preserves method parameters when activating a mutant" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class Gate4ArgumentSample
          def value(x)
            x + 1
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      mutant = Henitai::MutantGenerator.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new]
      ).first

      described_class.activate!(mutant)

      expect(Gate4ArgumentSample.new.value(3)).to eq(2)
    end
  end

  it "activates a mutant without AST metadata" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorNoAstSample
          def value
            1
          end
        end
      RUBY

      subject = Henitai::Subject.new(
        namespace: "ActivatorNoAstSample",
        method_name: "value",
        method_type: :instance,
        source_location: {
          file: path,
          range: 1..3
        },
        ast_node: nil
      )
      mutant = build_mutant(
        subject:,
        original_node: Parser::AST::Node.new(:int, [1]),
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: {
          file: path,
          start_line: 2,
          end_line: 2,
          start_col: 0,
          end_col: 1
        }
      )

      described_class.activate!(mutant)

      expect(ActivatorNoAstSample.new.value).to eq(2)
    end
  end

  it "patches define_method bodies" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorDefineMethodSample
          define_method(:value) do
            1 + 2
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      mutant = Henitai::MutantGenerator.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new]
      ).first

      described_class.activate!(mutant)

      expect(ActivatorDefineMethodSample.new.value).to eq(-1)
    end
  end

  it "infers the source file from AST metadata when none is provided" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorInferredSourceSample
          def value
            1
          end
        end
      RUBY

      resolved_subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      subject = Henitai::Subject.new(
        namespace: resolved_subject.namespace,
        method_name: resolved_subject.method_name,
        method_type: resolved_subject.method_type,
        source_location: nil,
        ast_node: resolved_subject.ast_node
      )
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(ActivatorInferredSourceSample.new.value).to eq(2)
    end
  end

  it "raises when source file metadata cannot be determined" do
    subject = Henitai::Subject.new(
      namespace: "MissingActivatorSource",
      method_name: "value",
      method_type: :instance,
      ast_node: Struct.new(:location).new(nil)
    )
    mutant = build_mutant(
      subject:,
      original_node: Parser::AST::Node.new(:int, [1]),
      mutated_node: Parser::AST::Node.new(:int, [2]),
      location: {
        file: "missing.rb",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 1
      }
    )

    expect { described_class.activate!(mutant) }.to raise_error(NameError)
  end

  it "raises when the source file is missing from AST metadata" do
    subject = Henitai::Subject.new(
      namespace: "MissingActivatorAstSource",
      method_name: "value",
      method_type: :instance,
      ast_node: nil
    )
    mutant = build_mutant(
      subject:,
      original_node: Parser::AST::Node.new(:int, [1]),
      mutated_node: Parser::AST::Node.new(:int, [2]),
      location: {
        file: "missing.rb",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 1
      }
    )

    expect { described_class.activate!(mutant) }.to raise_error(NameError)
  end

  it "raises when AST metadata has no expression location" do
    subject = Henitai::Subject.new(
      namespace: "MissingActivatorExpression",
      method_name: "value",
      method_type: :instance,
      ast_node: Struct.new(:location).new(Struct.new(:expression).new(nil))
    )
    mutant = build_mutant(
      subject:,
      original_node: Parser::AST::Node.new(:int, [1]),
      mutated_node: Parser::AST::Node.new(:int, [2]),
      location: {
        file: "missing.rb",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 1
      }
    )

    expect { described_class.activate!(mutant) }.to raise_error(NameError)
  end

  it "serializes full parameter sets when activating a mutant" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorParamsSample
          def value(a, b = 1, *rest, c:, d: 2, **kwrest, &block)
            a + b
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      mutant = Henitai::MutantGenerator.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new]
      ).first

      described_class.activate!(mutant)

      expect(
        ActivatorParamsSample.new.value(3, 4, 5, c: 6, d: 7, e: 8) { :ok }
      ).to eq(-1)
    end
  end

  it "supports anonymous rest and keyword rest parameters" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorAnonymousRestSample
          def value(*, **)
            1
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(ActivatorAnonymousRestSample.new.value(1, 2, a: 3)).to eq(2)
    end
  end

  it "supports forward arguments" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorForwardArgsSample
          def value(...)
            1
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).first
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [2]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(ActivatorForwardArgsSample.new.value(1, 2, a: 3)).to eq(2)
    end
  end

  it "mutates within rescue bodies" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorRescueSample
          def value(flag)
            begin
              raise "boom" if flag
              1
            rescue StandardError
              2
            end
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      original_node = find_nodes(subject.ast_node, :int).last
      mutant = build_mutant(
        subject:,
        original_node: original_node,
        mutated_node: Parser::AST::Node.new(:int, [3]),
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(ActivatorRescueSample.new.value(true)).to eq(3)
    end
  end

  it "leaves the method unchanged when the original node is not found" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorNoMatchSample
          def value
            1
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      unrelated_node = Parser::CurrentRuby.parse("2")
      mutant = build_mutant(
        subject:,
        original_node: unrelated_node,
        mutated_node: Parser::AST::Node.new(:int, [3]),
        location: location_for(find_nodes(subject.ast_node, :int).first)
      )

      described_class.activate!(mutant)

      expect(ActivatorNoMatchSample.new.value).to eq(1)
    end
  end

  it "leaves the method unchanged when the original node lacks location metadata" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, <<~RUBY)
        class ActivatorLocationlessSample
          def value
            1
          end
        end
      RUBY

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      locationless_node = Parser::AST::Node.new(:int, [1])
      mutant = build_mutant(
        subject:,
        original_node: locationless_node,
        mutated_node: Parser::AST::Node.new(:int, [3]),
        location: location_for(find_nodes(subject.ast_node, :int).first)
      )

      described_class.activate!(mutant)

      expect(ActivatorLocationlessSample.new.value).to eq(1)
    end
  end

  it "rejects wildcard subjects" do
    subject = Henitai::Subject.new(namespace: "Sample", method_name: nil)
    mutant = Struct.new(:subject, :mutated_node).new(
      subject,
      Parser::AST::Node.new(:int, [2])
    )

    expect { described_class.activate!(mutant) }
      .to raise_error(ArgumentError, /wildcard/i)
  end
end
