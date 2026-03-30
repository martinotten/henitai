# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe ".devcontainer/Dockerfile" do
  let(:dockerfile) do
    File.read(File.expand_path("../../.devcontainer/Dockerfile", __dir__))
  end

  it "uses the official Alpine Ruby base image" do
    expect(dockerfile).to include("FROM ruby:4.0.2-alpine")
  end

  it "installs the Codex CLI package" do
    expect(dockerfile).to include("npm install -g @openai/codex@0.116.0")
  end
end
# rubocop:enable RSpec/DescribeClass
