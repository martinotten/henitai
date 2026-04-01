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
      mutant = Henitai::Mutant.new(
        subject:,
        operator: "FakeOperator",
        nodes: {
          original: original_node,
          mutated: Parser::AST::Node.new(:int, [2])
        },
        description: "replace 1 with 2",
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
      mutant = Henitai::Mutant.new(
        subject:,
        operator: "FakeOperator",
        nodes: {
          original: original_node,
          mutated: Parser::AST::Node.new(:int, [2])
        },
        description: "replace 1 with 2",
        location: location_for(original_node)
      )

      described_class.activate!(mutant)

      expect(Sample.value).to eq(2)
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
