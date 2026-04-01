# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Operators::ArithmeticOperator do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Calculator", method_name: "calculate")
  end

  def mutate(source)
    described_class.new.mutate(parse(source), subject: mutation_subject).first
  end

  def expect_mutation(source, replacement, description)
    expect(mutate(source)).to have_attributes(
      description:,
      mutated_node: satisfy { |node| node.children[1] == replacement }
    )
  end

  def generate_descriptions(expression)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "example.rb")
      File.write(
        path,
        <<~RUBY
          class Example
            def calc
              #{expression}
            end
          end
        RUBY
      )

      subject = Henitai::SubjectResolver.new.resolve_from_files([path]).first
      mutants = Henitai::MutantGenerator.new.generate([subject], [described_class.new])
      mutants.map(&:description)
    end
  end

  it "declares the arithmetic send node type" do
    expect(described_class.node_types).to eq([:send])
  end

  it "mutates + to -" do
    expect_mutation("a + b", :-, "replaced + with -")
  end

  it "mutates - to +" do
    expect_mutation("a - b", :+, "replaced - with +")
  end

  it "mutates * to /" do
    expect_mutation("a * b", :/, "replaced * with /")
  end

  it "mutates / to *" do
    expect_mutation("a / b", :*, "replaced / with *")
  end

  it "mutates ** to *" do
    expect_mutation("a ** b", :*, "replaced ** with *")
  end

  it "mutates % to *" do
    expect_mutation("a % b", :*, "replaced % with *")
  end

  it "ignores non-arithmetic sends" do
    expect(described_class.new.mutate(parse("a.foo"), subject: mutation_subject)).to eq([])
  end

  it "mutates arithmetic with constants" do
    expect_mutation("Foo::BAR + 1", :-, "replaced + with -")
  end

  it "mutates arithmetic with method calls" do
    expect_mutation("foo + compute_value()", :-, "replaced + with -")
  end

  it "mutates arithmetic with float literals" do
    expect_mutation("1.5 + 2.0", :-, "replaced + with -")
  end

  it "traverses nested parentheses" do
    expect(generate_descriptions("((foo + 1) * 2)")).to contain_exactly(
      "replaced + with -",
      "replaced * with /"
    )
  end
end
