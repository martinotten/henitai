# frozen_string_literal: true

# rubocop:disable Metrics/MethodLength, RSpec/MultipleExpectations

require "json"
require "net/http"
require "spec_helper"

RSpec.describe Henitai::Reporter::Dashboard do
  def schema
    {
      schemaVersion: "1.0",
      thresholds: { high: 80, low: 60 },
      files: {}
    }
  end

  def result
    Struct.new(:to_stryker_schema).new(schema)
  end

  def dashboard(settings = {})
    described_class.new(config: Struct.new(:dashboard).new(settings))
  end

  def with_env(pairs)
    original = pairs.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    pairs.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end

    yield
  ensure
    original.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

  def capture_request(env: {}, **settings)
    http = instance_double(Net::HTTP)
    stub_dashboard_http(http)

    with_env(dashboard_environment(env)) do
      dashboard(settings).report(result)
    end
  end

  def dashboard_environment(overrides)
    {
      "STRYKER_DASHBOARD_API_KEY" => "secret-token",
      "GITHUB_REF_NAME" => "main",
      "GITHUB_REF" => nil,
      "GITHUB_SHA" => nil
    }.merge(overrides)
  end

  def stub_dashboard_http(http)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request) { |request| request }
  end

  it "uploads the schema for the configured project with api key auth and env version" do
    request = capture_request(
      project: "github.com/example/project",
      base_url: "https://dashboard.example.test"
    )

    expect(request.method).to eq("PUT")
    expect(request.path).to eq("/api/reports/github.com/example/project/main")
    expect(request["X-Api-Key"]).to eq("secret-token")
    expect(request["Content-Type"]).to eq("application/json")
    expect(request.body).to eq(JSON.generate(schema))
  end

  it "sets HTTP timeouts on dashboard uploads" do
    http = instance_double(Net::HTTP)
    reporter = dashboard(
      project: "github.com/example/project",
      base_url: "https://dashboard.example.test"
    )
    request = instance_double(Net::HTTP::Put)

    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request).and_return(request)
    allow(request).to receive(:body=)

    with_env(
      "STRYKER_DASHBOARD_API_KEY" => "secret-token",
      "GITHUB_REF_NAME" => "main",
      "GITHUB_REF" => nil,
      "GITHUB_SHA" => nil
    ) do
      reporter.report(result)
    end

    expect(http).to have_received(:open_timeout=).with(30)
    expect(http).to have_received(:read_timeout=).with(30)
  end

  it "falls back to the git remote when dashboard.project is absent" do
    reporter = dashboard(base_url: "https://dashboard.example.test")
    allow(reporter).to receive(:git_remote_url).and_return("git@github.com:acme/app.git")
    http = instance_double(Net::HTTP)
    stub_dashboard_http(http)

    with_env(
      "STRYKER_DASHBOARD_API_KEY" => "secret-token",
      "GITHUB_REF_NAME" => nil,
      "GITHUB_REF" => "refs/heads/main",
      "GITHUB_SHA" => nil
    ) do
      request = reporter.report(result)

      expect(request.path).to eq("/api/reports/github.com/acme/app/main")
    end
  end

  it "derives the version from a fuller GITHUB_REF when REF_NAME is missing" do
    request = nil

    with_env(
      "STRYKER_DASHBOARD_API_KEY" => "secret-token",
      "GITHUB_REF_NAME" => nil,
      "GITHUB_REF" => "refs/heads/feature/xyz",
      "GITHUB_SHA" => nil
    ) do
      request = capture_request(
        project: "github.com/example/project",
        base_url: "https://dashboard.example.test",
        env: {
          "GITHUB_REF_NAME" => nil,
          "GITHUB_REF" => "refs/heads/feature/xyz",
          "GITHUB_SHA" => nil
        }
      )
    end

    expect(request.path).to eq("/api/reports/github.com/example/project/feature%2Fxyz")
  end

  it "uses GITHUB_SHA when no ref variables are present" do
    http = instance_double(Net::HTTP)
    stub_dashboard_http(http)

    with_env(
      "STRYKER_DASHBOARD_API_KEY" => "secret-token",
      "GITHUB_REF_NAME" => nil,
      "GITHUB_REF" => nil,
      "GITHUB_SHA" => "deadbeef"
    ) do
      request = dashboard(
        project: "github.com/example/project",
        base_url: "https://dashboard.example.test"
      ).report(result)

      expect(request.path).to eq("/api/reports/github.com/example/project/deadbeef")
    end
  end

  it "uses the local branch when CI refs are unavailable" do
    reporter = dashboard(
      project: "github.com/example/project",
      base_url: "https://dashboard.example.test"
    )
    http = instance_double(Net::HTTP)
    stub_dashboard_http(http)
    allow(reporter).to receive(:git_branch_name).and_return("local-branch")

    with_env(
      "STRYKER_DASHBOARD_API_KEY" => "secret-token",
      "GITHUB_REF_NAME" => nil,
      "GITHUB_REF" => nil,
      "GITHUB_SHA" => nil
    ) do
      request = reporter.report(result)

      expect(request.path).to eq("/api/reports/github.com/example/project/local-branch")
    end
  end

  it "does not upload when the dashboard API key is missing" do
    allow(Net::HTTP).to receive(:start)

    with_env(
      "STRYKER_DASHBOARD_API_KEY" => nil,
      "GITHUB_REF_NAME" => "main",
      "GITHUB_REF" => nil,
      "GITHUB_SHA" => nil
    ) do
      expect(
        dashboard(
          project: "github.com/example/project",
          base_url: "https://dashboard.example.test"
        ).report(result)
      ).to be_nil
    end

    expect(Net::HTTP).not_to have_received(:start)
  end

  it "parses https git urls into dashboard project paths" do
    expect(
      described_class.project_from_git_url("https://github.com/acme/app.git")
    ).to eq("github.com/acme/app")
  end

  it "parses ssh git urls into dashboard project paths" do
    expect(
      described_class.project_from_git_url("git@github.com:acme/app.git")
    ).to eq("github.com/acme/app")
  end

  it "handles uri urls without a host" do
    expect(
      described_class.project_from_git_url("https:///acme/app.git")
    ).to eq("acme/app")
  end

  it "returns nil for blank git urls" do
    expect(described_class.project_from_git_url("")).to be_nil
  end
end

# rubocop:enable Metrics/MethodLength, RSpec/MultipleExpectations
