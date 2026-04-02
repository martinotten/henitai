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
end
