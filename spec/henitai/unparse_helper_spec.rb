# frozen_string_literal: true

require "spec_helper"
require "henitai/unparse_helper"

RSpec.describe Henitai::UnparseHelper do
  let(:host_class) do
    Class.new do
      include Henitai::UnparseHelper

      public :safe_unparse, :fallback_source
    end
  end
  let(:host) { host_class.new }

  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  describe "#safe_unparse" do
    it "unparses a supported node back to source" do
      node = parse("1 + 2")

      expect(host.safe_unparse(node)).to eq("1 + 2")
    end

    [
      Unparser::UnknownNodeError.new("unknown node"),
      Unparser::InvalidNodeError.new("invalid node", nil),
      Unparser::UnsupportedNodeError.new("unsupported node"),
      EncodingError.new("bad encoding")
    ].each do |error|
      it "falls back to fallback_source when Unparser raises #{error.class}" do
        node = parse("1 + 2")
        allow(Unparser).to receive(:unparse).with(node).and_raise(error)

        expect(host.safe_unparse(node)).to eq(host.fallback_source(node))
      end
    end

    it "does not rescue unrelated errors" do
      node = parse("1 + 2")
      allow(Unparser).to receive(:unparse).with(node).and_raise(NoMethodError)

      expect { host.safe_unparse(node) }.to raise_error(NoMethodError)
    end
  end

  describe "#fallback_source" do
    it "returns an empty string for a nil node" do
      expect(host.fallback_source(nil)).to eq("")
    end

    it "returns the node type when the node responds to #type" do
      node = parse("1 + 2")

      expect(host.fallback_source(node)).to eq(node.type.to_s)
    end

    it "returns the class name when the node does not respond to #type" do
      node = Object.new

      expect(host.fallback_source(node)).to eq("Object")
    end
  end
end
