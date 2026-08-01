# frozen_string_literal: true

require "spec_helper"
require "yaml"

# The supported-Ruby floor is stated in three places that must agree: the
# gemspec constraint users resolve against, the RuboCop target that decides
# which syntax the linter demands, and the CI matrix that proves the floor
# still works. Drift between them is silent — a RuboCop target above the
# gemspec floor makes the linter rewrite code into syntax the floor cannot
# parse (this is how `Enumerable#rfind` entered a Ruby 3.3-compatible
# codebase), and a matrix that never runs the floor never catches it.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Supported Ruby version" do
  def minimum_ruby_version
    spec = Gem::Specification.load(File.expand_path("../../henitai.gemspec", __dir__))
    requirement, version = spec.required_ruby_version.requirements.first

    raise "expected a `>=` floor, got #{requirement.inspect}" unless requirement == ">="

    version
  end

  def rubocop_target_ruby_version
    YAML.safe_load_file(File.expand_path("../../.rubocop.yml", __dir__))
        .fetch("AllCops").fetch("TargetRubyVersion").to_s
  end

  def ci_matrix_ruby_versions
    YAML.safe_load_file(File.expand_path("../../.github/workflows/ci.yml", __dir__))
        .fetch("jobs").fetch("test").fetch("strategy").fetch("matrix").fetch("ruby")
  end

  it "targets the same Ruby series in RuboCop as the gemspec requires" do
    expect(rubocop_target_ruby_version).to eq(minimum_ruby_version.segments.first(2).join("."))
  end

  it "runs the minimum supported Ruby in the CI test matrix" do
    expect(ci_matrix_ruby_versions).to include(minimum_ruby_version.to_s)
  end
end
# rubocop:enable RSpec/DescribeClass
