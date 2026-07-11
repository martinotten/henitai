# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operator do
  def stub_operator_constants(names)
    names.each do |name|
      stub_const(
        "Henitai::Operators::#{name}",
        Class.new(described_class)
      )
    end
  end

  it "returns light set operator instances in the documented order" do
    stub_operator_constants(described_class::LIGHT_SET)

    operators = described_class.for_set(:light)

    expect(operators.map { |operator| operator.class.name }).to eq(
      described_class::LIGHT_SET.map { |name| "Henitai::Operators::#{name}" }
    )
  end

  it "returns full set operator instances in the documented order" do
    stub_operator_constants(described_class::FULL_SET)

    operators = described_class.for_set(:full)

    expect(operators.map { |operator| operator.class.name }).to eq(
      described_class::FULL_SET.map { |name| "Henitai::Operators::#{name}" }
    )
  end

  it "returns the short class name as the operator name" do
    operator_class = stub_const("Henitai::Operators::FakeLongName", Class.new(described_class))
    expect(operator_class.new.name).to eq("FakeLongName")
  end

  it "requires subclasses to declare node types" do
    expect { described_class.node_types }
      .to raise_error(NotImplementedError, /Operator\.node_types must be defined/)
  end

  it "requires subclasses to implement mutation" do
    expect { described_class.new.mutate(nil, subject: nil) }
      .to raise_error(NotImplementedError, /Operator#mutate must be implemented/)
  end

  it "builds a mutant without location metadata when the node has no source location" do
    operator_class = stub_const(
      "Henitai::NoLocationOperator",
      Class.new(described_class) do
        def self.node_types
          [:int]
        end

        def mutate(node, subject:)
          [
            build_mutant(
              subject:,
              original_node: node,
              mutated_node: node,
              description: "no-op"
            )
          ]
        end
      end
    )

    node = Struct.new(:location).new(Struct.new(:expression).new(nil))

    mutant = operator_class.new.mutate(node, subject: Henitai::Subject.new(
      namespace: "Example",
      method_name: "example"
    )).first

    expect(mutant.location).to eq({})
  end

  it "builds full location metadata with symbol keys mirroring the node's source span" do
    operator_class = stub_const(
      "Henitai::LocationProbeOperator",
      Class.new(described_class) do
        def self.node_types
          [:send]
        end

        def mutate(node, subject:)
          [build_mutant(subject:, original_node: node, mutated_node: node, description: "probe")]
        end
      end
    )

    source = <<~RUBY
      foo(
        1
      )
    RUBY
    node = Henitai::SourceParser.parse(source, path: "example.rb")

    mutant = operator_class.new.mutate(node, subject: Henitai::Subject.new(
      namespace: "Example",
      method_name: "example"
    )).first

    expect(mutant.location).to eq(
      file: "example.rb",
      start_line: 1,
      end_line: 3,
      start_col: 0,
      end_col: 1
    )
  end
end
