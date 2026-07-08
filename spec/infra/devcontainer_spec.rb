# frozen_string_literal: true

require "json"
require "spec_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Dev container configuration" do
  let(:devcontainer_path) { File.expand_path("../../.devcontainer/devcontainer.json", __dir__) }
  let(:dockerfile_path) { File.expand_path("../../.devcontainer/Dockerfile", __dir__) }

  it "does not mount a worktree directory into the container" do
    mounts = JSON.parse(File.read(devcontainer_path)).fetch("mounts")

    expect(mounts.grep(/worktrees/)).to be_empty
  end

  it "does not create a worktree directory in the image" do
    dockerfile = File.read(dockerfile_path)

    expect(dockerfile).not_to include("/workspaces/worktrees")
  end
end
# rubocop:enable RSpec/DescribeClass
