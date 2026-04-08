# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::AssignmentExpression do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "assignment")
  end

  def mutate(source, type)
    node = find_nodes(parse(source), type).first

    described_class.new.mutate(node, subject: mutation_subject)
  end

  it "declares only or_asgn as its node type" do
    expect(described_class.node_types).to eq(%i[or_asgn])
  end

  it "removes ||= from local variable assignments" do
    mutant = mutate("x ||= compute", :or_asgn).first

    expect(mutant).to have_attributes(
      description: "removed ||=",
      mutated_node: satisfy { |node| node.type == :lvasgn }
    )
  end

  it "removes ||= from instance variable assignments" do
    mutant = mutate("@var ||= compute", :or_asgn).first

    expect(mutant).to have_attributes(
      description: "removed ||=",
      mutated_node: satisfy { |node| node.type == :ivasgn }
    )
  end

  it "removes ||= from method call assignments" do
    mutant = mutate("foo.bar ||= compute", :or_asgn).first

    expect(mutant).to have_attributes(
      description: "removed ||=",
      mutated_node: satisfy { |node| node.type == :send && node.children[1] == :bar= }
    )
  end

  it "removes ||= from element assignments" do
    mutant = mutate("foo[0] ||= compute", :or_asgn).first

    expect(mutant).to have_attributes(
      description: "removed ||=",
      mutated_node: satisfy { |node| node.type == :send && node.children[1] == :[]= }
    )
  end

  it "removes ||= from constant assignments" do
    mutant = mutate("Foo::BAR ||= compute", :or_asgn).first

    expect(mutant).to have_attributes(
      description: "removed ||=",
      mutated_node: satisfy { |node| node.type == :casgn }
    )
  end

  it "ignores unsupported coalesce assignment targets" do
    node = Parser::AST::Node.new(
      :or_asgn,
      [
        Parser::AST::Node.new(:int, [1]),
        Parser::AST::Node.new(:send, [nil, :compute])
      ]
    )

    expect(described_class.new.mutate(node, subject: mutation_subject)).to eq([])
  end

  # Regression guard: the full operator set must not produce two identical
  # mutants for x += 1 (one from AssignmentExpression, one from UpdateOperator).
  it "does not duplicate the += → -= mutant produced by UpdateOperator in the full set" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "lib/sample.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, <<~RUBY)
        class Sample
          def run
            x += 1
          end
        end
      RUBY

      subjects = Henitai::SubjectResolver.new.resolve_from_files([path])
      mutants  = Henitai::MutantGenerator.new.generate(
        subjects,
        Henitai::Operator.for_set(:full)
      )

      op_asgn_swaps = mutants.select do |m|
        m.description.match?(/replaced \+= with -=|replaced \+ with -/)
      end

      expect(op_asgn_swaps.size).to eq(1),
        "expected exactly 1 += → -= mutant, got #{op_asgn_swaps.size}: " \
        "#{op_asgn_swaps.map { |m| "#{m.operator}: #{m.description}" }.inspect}"
    end
  end
end
