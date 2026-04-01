# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators do
  it "loads the arithmetic operator as a Henitai operator" do
    expect(described_class::ArithmeticOperator).to be < Henitai::Operator
  end

  it "loads the assignment operator as a Henitai operator" do
    expect(described_class::AssignmentExpression).to be < Henitai::Operator
  end
end
