# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Pre-commit hook" do
  it "runs rubocop, rspec, and integration smoke tests" do
    hook = File.read(File.expand_path("../../.githooks/pre-commit", __dir__))

    expect(hook.lines.map(&:strip)).to eq(
      [
        "#!/bin/sh",
        "set -eu",
        "",
        "repo_root=$(git rev-parse --show-toplevel)",
        "cd \"$repo_root\"",
        "",
        "bundle exec rubocop --parallel",
        "bundle exec rspec",
        "bundle exec rake smoke:integration:all"
      ]
    )
  end
end
# rubocop:enable RSpec/DescribeClass
