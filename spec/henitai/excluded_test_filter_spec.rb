# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ExcludedTestFilter do
  def reject(tests, patterns)
    described_class.new(patterns:).reject(tests)
  end

  it "drops tests matching a glob, keeping the rest" do
    tests = %w[
      spec/henitai/foo_spec.rb
      spec/henitai/cli_spec.rb
      spec/henitai/integration/rspec_spec.rb
    ]
    patterns = ["spec/henitai/cli_spec.rb", "spec/henitai/integration/*_spec.rb"]

    expect(reject(tests, patterns)).to eq(["spec/henitai/foo_spec.rb"])
  end

  it "returns every test when no patterns are configured" do
    expect(reject(["a_spec.rb"], [])).to eq(["a_spec.rb"])
  end

  it "returns every test when patterns are nil" do
    expect(reject(["a_spec.rb"], nil)).to eq(["a_spec.rb"])
  end

  # FNM_PATHNAME: a single * must not match across a directory separator, or a
  # narrow exclude would silently drop a whole subtree of tests.
  it "does not let a glob wildcard cross directory boundaries" do
    tests = %w[spec/a/deep/thing_spec.rb spec/a/thing_spec.rb]

    expect(reject(tests, ["spec/a/*_spec.rb"])).to eq(["spec/a/deep/thing_spec.rb"])
  end

  it "matches a pattern that does span directories explicitly" do
    tests = %w[spec/a/deep/thing_spec.rb spec/a/thing_spec.rb]

    expect(reject(tests, ["spec/a/*/*_spec.rb"])).to eq(["spec/a/thing_spec.rb"])
  end

  # Paths are compared after expansion, so a relative pattern still matches an
  # absolute test path and vice versa.
  it "matches regardless of whether the path is relative or absolute" do
    absolute = File.expand_path("spec/a/thing_spec.rb")

    expect(reject([absolute], ["spec/a/thing_spec.rb"])).to be_empty
  end

  it "keeps a test that matches no pattern" do
    expect(reject(["spec/b/other_spec.rb"], ["spec/a/*_spec.rb"]))
      .to eq(["spec/b/other_spec.rb"])
  end

  it "returns an empty list for no tests" do
    expect(reject([], ["spec/a/*_spec.rb"])).to be_empty
  end
end
