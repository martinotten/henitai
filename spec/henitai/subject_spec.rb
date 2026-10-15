# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Subject do
  it "parses class method expressions" do
    subject = described_class.parse("Foo::Bar.baz")

    expect(subject.expression).to eq("Foo::Bar.baz")
  end

  it "parses predicate, bang, setter and operator method names" do
    expressions = %w[Foo#empty? Foo#save! Foo#name= Foo#== Foo#[] Foo::Bar.<=>]

    expect(expressions.map { |expression| described_class.parse(expression).method_name })
      .to eq(%w[empty? save! name= == [] <=>])
  end

  it "parses wildcard expressions" do
    subject = described_class.parse("Foo::Bar*")

    expect(subject.expression).to eq("Foo::Bar*")
  end

  it "initializes from explicit namespace metadata" do
    subject = described_class.new(
      namespace: "Foo::Bar",
      method_name: "baz",
      method_type: :class,
      source_location: {
        file: "foo/bar.rb",
        range: 12..18
      }
    )

    expect([subject.source_file, subject.source_range]).to eq(
      ["foo/bar.rb", 12..18]
    )
  end

  it "rejects unknown keyword options" do
    expect do
      described_class.new(namespace: "Foo", method_name: "bar", unsupported: true)
    end.to raise_error(ArgumentError, /unknown keyword: :unsupported/)
  end
end
