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

  it "declares compound assignment node types" do
    expect(described_class.node_types).to eq(%i[op_asgn or_asgn])
  end

  it "mutates += to -=" do
    mutant = mutate("x += 1", :op_asgn).first

    expect(mutant).to have_attributes(
      description: "replaced + with -",
      mutated_node: satisfy { |node| node.children[1] == :- }
    )
  end

  it "mutates -= to +=" do
    mutant = mutate("x -= 1", :op_asgn).first

    expect(mutant).to have_attributes(
      description: "replaced - with +",
      mutated_node: satisfy { |node| node.children[1] == :+ }
    )
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

  it "ignores unsupported compound assignments" do
    expect(mutate("x *= 1", :op_asgn)).to eq([])
  end
end
