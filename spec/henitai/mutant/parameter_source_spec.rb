# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Mutant::ParameterSource do
  subject(:parameter_source) { described_class.new }

  describe "#build" do
    it "returns an empty string when the node has no arguments" do
      node = Parser::CurrentRuby.parse("def foo; end")

      expect(parameter_source.build(node)).to eq("")
    end

    it "returns an empty string for nodes without a method-argument shape" do
      node = Parser::CurrentRuby.parse("1")

      expect(parameter_source.build(node)).to eq("")
    end

    it "renders required positional arguments" do
      node = Parser::CurrentRuby.parse("def foo(a, b); end")

      expect(parameter_source.build(node)).to eq("a, b")
    end

    it "renders optional arguments with their unparsed default" do
      node = Parser::CurrentRuby.parse("def foo(a = 1 + 2); end")

      expect(parameter_source.build(node)).to eq("a = 1 + 2")
    end

    it "renders a named rest argument" do
      node = Parser::CurrentRuby.parse("def foo(*rest); end")

      expect(parameter_source.build(node)).to eq("*rest")
    end

    it "renders a bare rest argument" do
      node = Parser::CurrentRuby.parse("def foo(*); end")

      expect(parameter_source.build(node)).to eq("*")
    end

    it "renders required keyword arguments" do
      node = Parser::CurrentRuby.parse("def foo(key:); end")

      expect(parameter_source.build(node)).to eq("key:")
    end

    it "renders optional keyword arguments with their unparsed default" do
      node = Parser::CurrentRuby.parse("def foo(key: 1 + 2); end")

      expect(parameter_source.build(node)).to eq("key: 1 + 2")
    end

    it "renders a named keyword-rest argument" do
      node = Parser::CurrentRuby.parse("def foo(**kwargs); end")

      expect(parameter_source.build(node)).to eq("**kwargs")
    end

    it "renders a bare keyword-rest argument" do
      node = Parser::CurrentRuby.parse("def foo(**); end")

      expect(parameter_source.build(node)).to eq("**")
    end

    it "renders a block argument" do
      node = Parser::CurrentRuby.parse("def foo(&blk); end")

      expect(parameter_source.build(node)).to eq("&blk")
    end

    it "renders argument-forwarding as expanded splat/kwargs/block params" do
      node = Parser::CurrentRuby.parse("def foo(...); end")

      expect(parameter_source.build(node)).to eq("*args, **kwargs, &block")
    end

    it "joins a mix of argument kinds in declaration order" do
      node = Parser::CurrentRuby.parse("def foo(a, b = 1, *rest, key:, opt: 2, **kw, &blk); end")

      expect(parameter_source.build(node)).to eq("a, b = 1, *rest, key:, opt: 2, **kw, &blk")
    end

    it "reads arguments from a singleton method definition" do
      node = Parser::CurrentRuby.parse("def self.foo(a, b); end")

      expect(parameter_source.build(node)).to eq("a, b")
    end

    it "reads arguments from a block node" do
      node = Parser::CurrentRuby.parse("foo { |a, b| }")

      expect(parameter_source.build(node)).to eq("a, b")
    end

    it "ignores unsupported argument nodes" do
      unsupported = Parser::AST::Node.new(:unsupported)
      arguments = Parser::AST::Node.new(:args, [unsupported])
      node = Parser::AST::Node.new(:def, [:foo, arguments, nil])

      expect(parameter_source.build(node)).to eq("")
    end

    it "wraps unparse failures on default values as Unparser::UnsupportedNodeError" do
      node = Parser::CurrentRuby.parse("def foo(a = 1); end")
      allow(Unparser).to receive(:unparse).and_raise(StandardError, "boom")

      expect { parameter_source.build(node) }.to raise_error(Unparser::UnsupportedNodeError, "boom")
    end
  end
end
