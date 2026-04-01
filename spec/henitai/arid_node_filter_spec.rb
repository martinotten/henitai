# frozen_string_literal: true

require "parser/current"
require "spec_helper"

RSpec.describe Henitai::AridNodeFilter do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def fake_node(type:, children:, location: nil)
    Struct.new(:type, :children, :location).new(type, children, location)
  end

  def config(ignore_patterns: [])
    Struct.new(:ignore_patterns).new(ignore_patterns)
  end

  it "suppresses nodes matched by a configured ignore pattern" do
    node = parse("foo.bar")

    expect(described_class.new.suppressed?(node, config(ignore_patterns: ["foo\\.bar"]))).to be(true)
  end

  it "treats a nil config as having no ignore patterns" do
    node = parse("foo.bar")

    expect(described_class.new.suppressed?(node, nil)).to be(false)
  end

  it "returns false for a node without source location" do
    node = Parser::AST::Node.new(:int, [1])

    expect(described_class.new.suppressed?(node, config)).to be(false)
  end

  it "suppresses direct output helpers" do
    node = parse('puts "x"')

    expect(described_class.new.suppressed?(node, config)).to be(true)
  end

  it "suppresses direct debugger helpers" do
    node = parse("byebug")

    expect(described_class.new.suppressed?(node, config)).to be(true)
  end

  it "suppresses Rails logger calls" do
    node = parse('Rails.logger.warn("x")')

    expect(described_class.new.suppressed?(node, config)).to be(true)
  end

  it "suppresses debugger calls" do
    node = parse("binding.pry")

    expect(described_class.new.suppressed?(node, config)).to be(true)
  end

  it "suppresses memoization assignments" do
    node = parse("@foo ||= compute")

    expect(described_class.new.suppressed?(node, config)).to be(true)
  end

  it "suppresses RSpec DSL blocks" do
    node = parse("let(:x) { 1 }")

    expect(described_class.new.suppressed?(node, config)).to be(true)
  end

  it "suppresses invariant helper calls" do
    node = parse("foo.is_a?(String)")

    expect(described_class.new.suppressed?(node, config)).to be(true)
  end

  it "does not suppress malformed send nodes" do
    node = Parser::AST::Node.new(:send, [nil, nil])

    expect(described_class.new.suppressed?(node, config)).to be(false)
  end

  it "does not suppress bare pry calls" do
    node = parse("pry")

    expect(described_class.new.suppressed?(node, config)).to be(false)
  end

  it "does not suppress malformed block nodes" do
    node = fake_node(
      type: :block,
      children: [nil, fake_node(type: :args, children: []), fake_node(type: :int, children: [1])]
    )

    expect(described_class.new.suppressed?(node, config)).to be(false)
  end

  it "does not suppress logger-like nodes without a Rails receiver" do
    node = fake_node(
      type: :send,
      children: [
        fake_node(type: :send, children: [nil, :logger]),
        :warn
      ]
    )

    expect(described_class.new.suppressed?(node, config)).to be(false)
  end

  it "does not suppress an ordinary send node" do
    node = parse("foo.bar")

    expect(described_class.new.suppressed?(node, config)).to be(false)
  end
end
