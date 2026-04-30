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
end
# rubocop:enable RSpec/DescribeClass
