# frozen_string_literal: true

# rubocop:disable RSpec/MultipleExpectations

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

  def fake_metadata(project: "github.com/example/project", version: "main", api_key: "secret-token")
    instance_double(
      Henitai::Reporter::DashboardMetadataProvider,
      project: project, version: version, api_key: api_key
    )
  end

  def with_env(key, value)
    original = ENV.fetch(key, nil)

    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end

    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end

  def dashboard(base_url: nil, metadata_provider: fake_metadata)
    settings = base_url ? { base_url: base_url } : {}
    described_class.new(
      config: Struct.new(:dashboard).new(settings),
      metadata_provider: metadata_provider
    )
  end

  def stub_dashboard_http(http)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request) { |request| request }
  end

  it "uploads the schema for the configured project with api key auth and env version" do
    http = instance_double(Net::HTTP)
    stub_dashboard_http(http)

    request = dashboard(
      base_url: "https://dashboard.example.test",
      metadata_provider: fake_metadata(project: "github.com/example/project", version: "main")
    ).report(result)

    expect(request.method).to eq("PUT")
    expect(request.path).to eq("/api/reports/github.com/example/project/main")
    expect(request["X-Api-Key"]).to eq("secret-token")
    expect(request["Content-Type"]).to eq("application/json")
    expect(request.body).to eq(JSON.generate(schema))
  end

  it "uses the default metadata provider when none is injected" do
    http = instance_double(Net::HTTP)
    stub_dashboard_http(http)

    with_env("GITHUB_REF_NAME", "main") do
      with_env("STRYKER_DASHBOARD_API_KEY", "secret-token") do
        request = described_class.new(
          config: Struct.new(:dashboard).new(
            {
              base_url: "https://dashboard.example.test",
              project: "github.com/example/project"
            }
          )
        ).report(result)

        expect(request.path).to eq("/api/reports/github.com/example/project/main")
        expect(request["X-Api-Key"]).to eq("secret-token")
      end
    end

    expect(Net::HTTP).to have_received(:start).with("dashboard.example.test", 443, use_ssl: true)
  end

  it "includes a configured base path and explicit port in dashboard uploads" do
    http = instance_double(Net::HTTP)
    stub_dashboard_http(http)

    request = dashboard(base_url: "https://dashboard.example.test:8443/team/").report(result)

    expect(request.path).to eq("/team/api/reports/github.com/example/project/main")
    expect(Net::HTTP).to have_received(:start).with("dashboard.example.test", 8443, use_ssl: true)
  end

  it "disables SSL for http base URLs" do
    http = instance_double(Net::HTTP)
    stub_dashboard_http(http)

    request = dashboard(base_url: "http://dashboard.example.test").report(result)

    expect(request.path).to eq("/api/reports/github.com/example/project/main")
    expect(Net::HTTP).to have_received(:start).with("dashboard.example.test", 80, use_ssl: false)
  end

  it "disables SSL for non-https schemes" do
    http = instance_double(Net::HTTP)
    stub_dashboard_http(http)

    request = dashboard(base_url: "wss://dashboard.example.test").report(result)

    expect(request.path).to eq("/api/reports/github.com/example/project/main")
    expect(Net::HTTP).to have_received(:start).with("dashboard.example.test", 443, use_ssl: false)
  end

  it "sets HTTP timeouts on dashboard uploads" do
    http = instance_double(Net::HTTP)
    request = instance_double(Net::HTTP::Put)

    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request).and_return(request)
    allow(request).to receive(:body=)

    dashboard(base_url: "https://dashboard.example.test").report(result)

    expect(http).to have_received(:open_timeout=).with(30)
    expect(http).to have_received(:read_timeout=).with(30)
  end

  it "does not upload when the dashboard API key is missing" do
    allow(Net::HTTP).to receive(:start)

    expect(
      dashboard(
        base_url: "https://dashboard.example.test",
        metadata_provider: fake_metadata(api_key: nil)
      ).report(result)
    ).to be_nil
    expect(Net::HTTP).not_to have_received(:start)
  end

  it "does not upload when the version cannot be determined" do
    allow(Net::HTTP).to receive(:start)

    expect(
      dashboard(
        base_url: "https://dashboard.example.test",
        metadata_provider: fake_metadata(version: nil)
      ).report(result)
    ).to be_nil
    expect(Net::HTTP).not_to have_received(:start)
  end

  it "does not upload when the project cannot be determined" do
    allow(Net::HTTP).to receive(:start)

    expect(
      dashboard(
        base_url: "https://dashboard.example.test",
        metadata_provider: fake_metadata(project: nil)
      ).report(result)
    ).to be_nil
    expect(Net::HTTP).not_to have_received(:start)
  end

  it "enables SSL when the base URL scheme is https" do
    http = instance_double(Net::HTTP)
    stub_dashboard_http(http)

    dashboard(base_url: "https://dashboard.example.test").report(result)

    expect(Net::HTTP).to have_received(:start).with("dashboard.example.test", 443, use_ssl: true)
  end

  it "handles a trailing slash in the base URL without doubling path separators" do
    http = instance_double(Net::HTTP)
    stub_dashboard_http(http)

    request = dashboard(base_url: "https://dashboard.example.test/").report(result)

    expect(request.path).to eq("/api/reports/github.com/example/project/main")
  end

  it "falls back to the default base URL when base_url is not configured" do
    http = instance_double(Net::HTTP)
    stub_dashboard_http(http)

    request = dashboard.report(result)

    expect(request.path).to start_with("/api/reports/github.com/example/project/")
  end

  it "url-encodes project and version segments" do
    http = instance_double(Net::HTTP)
    stub_dashboard_http(http)

    request = dashboard(
      base_url: "https://dashboard.example.test",
      metadata_provider: fake_metadata(
        project: :"github.com/example/project",
        version: :"release/v2.0"
      )
    ).report(result)

    expect(request.path).to eq("/api/reports/github.com/example/project/release%2Fv2.0")
  end
end

# rubocop:enable RSpec/MultipleExpectations
