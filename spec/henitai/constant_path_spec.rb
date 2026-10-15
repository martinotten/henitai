# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ConstantPath do
  def node(source)
    Henitai::SourceParser.parse(source)
  end

  describe ".of" do
    it "names relative, nested and root-qualified constants as written" do
      expect(%w[Foo Foo::Bar ::Foo::Bar].map { |source| described_class.of(node(source)) })
        .to eq(%w[Foo Foo::Bar ::Foo::Bar])
    end

    it "names the target of a constant assignment" do
      expect(described_class.of(node("Outer::Point = 1"))).to eq("Outer::Point")
    end

    it "returns nil for other nodes" do
      expect([described_class.of(node("foo")), described_class.of(nil)]).to eq([nil, nil])
    end
  end

  describe ".qualify" do
    it "nests a relative name in the namespace" do
      expect(described_class.qualify("Outer", "Inner")).to eq("Outer::Inner")
    end

    it "ignores the namespace for a root-qualified name" do
      expect(described_class.qualify("Outer", "::Top::Inner")).to eq("Top::Inner")
    end

    it "keeps the name without a namespace and the namespace without a name" do
      expect([described_class.qualify(nil, "Foo"), described_class.qualify("", "Foo"),
              described_class.qualify("Outer", nil), described_class.qualify("Outer", "")])
        .to eq(%w[Foo Foo Outer Outer])
    end
  end

  describe ".owner" do
    it "is the namespace for self and the qualified constant for a constant" do
      expect([described_class.owner(node("self"), "Outer"), described_class.owner(node("Other"), "Outer")])
        .to eq(%w[Outer Outer::Other])
    end

    it "is nil for any other receiver" do
      expect(described_class.owner(node("registry"), "Outer")).to be_nil
    end
  end
end
