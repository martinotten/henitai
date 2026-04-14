# frozen_string_literal: true

require "spec_helper"
require "yaml"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "CI workflow" do
  it "runs rubocop, steep, rspec, and integration smoke tests in the test job" do
    workflow = YAML.safe_load_file(
      File.expand_path("../../.github/workflows/ci.yml", __dir__)
    )

    commands = workflow.fetch("jobs").fetch("test").fetch("steps").filter_map do |step|
      step["run"]
    end

    expect(commands).to include(
      "bundle exec rubocop --parallel",
      "bundle exec steep check",
      "bundle exec rspec",
      "bundle exec rake smoke:integration:all"
    )
  end
end
# rubocop:enable RSpec/DescribeClass
