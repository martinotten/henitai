# frozen_string_literal: true

require "spec_helper"
require "yaml"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "CI workflow" do
  it "runs rubocop, steep, rspec, integration smoke tests and the oracle corpus in the test job" do
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
      "bundle exec ruby bin/verify-process-free-specs",
      "bundle exec rake smoke:integration:all",
      "bundle exec rake oracle"
    )
  end
end
# rubocop:enable RSpec/DescribeClass
