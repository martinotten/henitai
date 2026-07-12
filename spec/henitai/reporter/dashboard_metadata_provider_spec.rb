# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Reporter::DashboardMetadataProvider do
  def fake_env(values = {})
    Hash.new(nil).merge(values)
  end

  def fake_git_executor(remote: nil, branch: nil)
    status = Struct.new(:ok) do
      def success? = ok
    end
    Class.new do
      define_method(:capture2) do |*args|
        case args[1]
        when "remote" then [remote.to_s, status.new(!remote.nil?)]
        when "rev-parse" then [branch.to_s, status.new(!branch.nil?)]
        end
      end
    end.new
  end

  def provider(dashboard_config: {}, env: fake_env, git_executor: fake_git_executor)
    described_class.new(dashboard_config: dashboard_config, env: env, git_executor: git_executor)
  end

  describe "#project" do
    it "uses the configured project when present" do
      expect(provider(dashboard_config: { project: "github.com/example/project" }).project)
        .to eq("github.com/example/project")
    end

    it "falls back to the injected git remote when not configured" do
      executor = fake_git_executor(remote: "git@github.com:acme/app.git")

      expect(provider(git_executor: executor).project).to eq("github.com/acme/app")
    end

    it "invokes git with the remote lookup command" do
      status = Struct.new(:success?).new(true)
      executor = class_double(Open3)
      allow(executor).to receive(:capture2)
        .with("git", "remote", "get-url", "origin")
        .and_return(["git@github.com:acme/app.git", status])

      provider(git_executor: executor).project

      expect(executor).to have_received(:capture2).with("git", "remote", "get-url", "origin")
    end

    it "invokes git with the branch lookup command" do
      status = Struct.new(:success?).new(true)
      executor = class_double(Open3)
      allow(executor).to receive(:capture2)
        .with("git", "rev-parse", "--abbrev-ref", "HEAD")
        .and_return(["feature", status])

      provider(git_executor: executor).version

      expect(executor).to have_received(:capture2).with("git", "rev-parse", "--abbrev-ref", "HEAD")
    end

    it "returns nil when neither configuration nor git remote resolve" do
      expect(provider.project).to be_nil
    end
  end

  describe "#version" do
    it "prefers GITHUB_REF_NAME" do
      env = fake_env("GITHUB_REF_NAME" => "main")

      expect(provider(env: env).version).to eq("main")
    end

    it "falls back to a stripped GITHUB_REF when REF_NAME is blank" do
      env = fake_env("GITHUB_REF" => "refs/heads/feature/xyz")

      expect(provider(env: env).version).to eq("feature/xyz")
    end

    it "falls back to GITHUB_SHA when no ref variables are present" do
      env = fake_env("GITHUB_SHA" => "deadbeef")

      expect(provider(env: env).version).to eq("deadbeef")
    end

    it "falls back to the injected git branch when no CI env vars are present" do
      executor = fake_git_executor(branch: "local-branch")

      expect(provider(git_executor: executor).version).to eq("local-branch")
    end

    it "returns nil when no CI env vars or git branch resolve" do
      expect(provider.version).to be_nil
    end
  end

  describe "#api_key" do
    it "reads STRYKER_DASHBOARD_API_KEY from the injected env" do
      env = fake_env("STRYKER_DASHBOARD_API_KEY" => "secret-token")

      expect(provider(env: env).api_key).to eq("secret-token")
    end

    it "returns nil when the key is absent" do
      expect(provider.api_key).to be_nil
    end
  end

  describe ".project_from_git_url" do
    it "parses https git urls into dashboard project paths" do
      expect(described_class.project_from_git_url("https://github.com/acme/app.git"))
        .to eq("github.com/acme/app")
    end

    it "parses ssh git urls into dashboard project paths" do
      expect(described_class.project_from_git_url("git@github.com:acme/app.git"))
        .to eq("github.com/acme/app")
    end

    it "handles uri urls without a host" do
      expect(described_class.project_from_git_url("https:///acme/app.git")).to eq("acme/app")
    end

    it "returns nil for blank git urls" do
      expect(described_class.project_from_git_url("")).to be_nil
    end

    it "returns nil for SSH git URLs without a path component" do
      expect(described_class.project_from_git_url("git@github.com")).to be_nil
    end
  end
end
