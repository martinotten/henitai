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
end
