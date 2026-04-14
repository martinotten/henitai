# frozen_string_literal: true

require "json"
require "spec_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Dev container configuration" do
  let(:config_path) { File.expand_path("../../.devcontainer/devcontainer.json", __dir__) }
  let(:dockerfile_path) { File.expand_path("../../.devcontainer/Dockerfile", __dir__) }
  let(:config) { JSON.parse(File.read(config_path)) }
  let(:dockerfile) { File.read(dockerfile_path) }

  it "uses a Docker volume for Bundler state" do
    expect(config.fetch("mounts")).to include(
      "source=henitai-bundle,target=/usr/local/bundle,type=volume"
    )
  end

  it "sets the bundle path inside the container" do
    expect(config.fetch("remoteEnv").fetch("BUNDLE_PATH")).to eq("/usr/local/bundle")
  end

  it "installs RTK in the image" do
    expect(dockerfile).to include(
      "curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh"
    )
  end

  it "exposes RTK on the PATH" do
    expect(dockerfile).to include("ln -s /root/.local/bin/rtk /usr/local/bin/rtk")
  end

  it "bootstraps Codex with RTK after create" do
    expect(config.fetch("postCreateCommand")).to eq(
      "bundle install && rtk init -g --codex --auto-patch"
    )
  end
end
# rubocop:enable RSpec/DescribeClass
