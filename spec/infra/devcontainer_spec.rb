# frozen_string_literal: true

require "json"
require "spec_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Dev container configuration" do
  let(:config_path) { File.expand_path("../../.devcontainer/devcontainer.json", __dir__) }
  let(:config) { JSON.parse(File.read(config_path)) }

  it "uses a Docker volume for Bundler state" do
    expect(config.fetch("mounts")).to include(
      "source=henitai-bundle,target=/usr/local/bundle,type=volume"
    )
  end

  it "sets the bundle path inside the container" do
    expect(config.fetch("remoteEnv").fetch("BUNDLE_PATH")).to eq("/usr/local/bundle")
  end
end
# rubocop:enable RSpec/DescribeClass
