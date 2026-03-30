# frozen_string_literal: true

require "spec_helper"
require "open3"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Steep Phase 1 scope" do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:steepfile) { File.join(root, "Steepfile") }

  it "limits the checked files to the public API surface" do
    expected = [
      "lib/henitai.rb",
      "lib/henitai/configuration.rb",
      "lib/henitai/subject.rb",
      "lib/henitai/mutant.rb",
      "lib/henitai/operator.rb",
      "lib/henitai/integration.rb",
      "lib/henitai/reporter.rb",
      "lib/henitai/result.rb",
      "lib/henitai/runner.rb"
    ]

    actual = File.readlines(steepfile).filter_map do |line|
      match = line.match(/^\s*check\s+"(.+)"\s*$/)
      match&.[](1)
    end

    expect(actual).to eq(expected)
  end

  it "typechecks the public API surface with Steep" do
    stdout, stderr, status = Open3.capture3("bundle exec steep check", chdir: root)

    expect(status.success?).to be(true), [stdout, stderr].reject(&:empty?).join("\n")
  end
end
# rubocop:enable RSpec/DescribeClass
