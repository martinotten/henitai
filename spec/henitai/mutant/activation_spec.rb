# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Mutant::Activation do
  it "round-trips through its recipe hash" do
    activation = described_class.new(source: "class A\n  def b = 1\nend\n", mode: :toplevel, file: "/x/a.rb",
                                     line: 1, def_offset: 1)

    expect(described_class.from_h(JSON.parse(JSON.generate(activation.to_h)))).to eq(activation)
  end
end
