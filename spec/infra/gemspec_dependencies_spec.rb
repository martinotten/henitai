# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Gemspec dependencies" do
  it "declares minitest for the minitest integration under Bundler" do
    spec = Gem::Specification.load(
      File.expand_path("../../henitai.gemspec", __dir__)
    )

    dependency_names = spec.runtime_dependencies.map(&:name)

    expect(dependency_names).to include("minitest")
  end

  it "allows the patched sqlite3 release" do
    spec = Gem::Specification.load(
      File.expand_path("../../henitai.gemspec", __dir__)
    )
    dependency = spec.runtime_dependencies.find { |item| item.name == "sqlite3" }

    expect(dependency.requirement.satisfied_by?(Gem::Version.new("2.9.5"))).to be(true)
  end

  it "rejects the vulnerable sqlite3 release" do
    spec = Gem::Specification.load(
      File.expand_path("../../henitai.gemspec", __dir__)
    )
    dependency = spec.runtime_dependencies.find { |item| item.name == "sqlite3" }

    expect(dependency.requirement.satisfied_by?(Gem::Version.new("2.9.4"))).to be(false)
  end

  it "locks the root bundle to a patched json release" do
    path = File.expand_path("../../Gemfile.lock", __dir__)
    version = File.read(path)[/^    json \(([^)]+)\)$/, 1]

    expect(Gem::Version.new(version)).to be >= Gem::Version.new("2.21.2")
  end
end
# rubocop:enable RSpec/DescribeClass
