# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Mutant::Activation do
  it "round-trips through its recipe hash" do
    activation = described_class.new(source: "class A\n  def b = 1\nend\n", mode: :toplevel, file: "/x/a.rb",
                                     line: 1, def_offset: 1)

    expect(described_class.from_h(JSON.parse(JSON.generate(activation.to_h)))).to eq(activation)
  end

  it "round-trips the lexical scope, owner and singleton flag of a toplevel activation" do
    activation = described_class.new(source: "class A\n  def self.b = 1\nend\n", mode: :toplevel, file: "/x/a.rb",
                                     line: 2, def_offset: 1, lexical_scope: ["class A"], owner: "self",
                                     singleton: true)

    restored = described_class.from_h(JSON.parse(JSON.generate(activation.to_h)))

    expect([restored.lexical_scope, restored.owner, restored.singleton]).to eq([["class A"], "self", true])
  end
end
