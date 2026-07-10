# frozen_string_literal: true

require "open3"
require "spec_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Steep Phase 1 execution" do
  it "typechecks the public API surface with Steep" do
    root = File.expand_path("../..", __dir__)
    stdout, stderr, status = Open3.capture3("bundle exec steep check", chdir: root)

    expect(status.success?).to be(true), [stdout, stderr].reject(&:empty?).join("\n")
  end
end
# rubocop:enable RSpec/DescribeClass
