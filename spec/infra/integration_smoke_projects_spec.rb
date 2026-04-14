# frozen_string_literal: true

require "open3"
require "spec_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Integration smoke projects" do
  let(:root) { File.expand_path("../..", __dir__) }

  def run_task(name)
    Open3.capture3("bundle", "exec", "rake", name, chdir: root)
  end

  it "runs the rspec smoke project through rake" do
    stdout, stderr, status = run_task("smoke:integration:rspec")

    expect(status.success?).to be(true), [stdout, stderr].reject(&:empty?).join("\n")
  end

  it "runs the minitest smoke project through rake" do
    stdout, stderr, status = run_task("smoke:integration:minitest")

    expect(status.success?).to be(true), [stdout, stderr].reject(&:empty?).join("\n")
  end
end
# rubocop:enable RSpec/DescribeClass
