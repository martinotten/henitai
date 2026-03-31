# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Subject do
  it "parses class method expressions" do
    subject = described_class.parse("Foo::Bar.baz")

    expect(subject.expression).to eq("Foo::Bar.baz")
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
end
