# frozen_string_literal: true

require "json"
require "spec_helper"
require "henitai/configuration_validator"
require "yaml"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Configuration schema" do
  let(:schema_path) { File.expand_path("../../assets/schema/henitai.schema.json", __dir__) }
  let(:sample_config_path) { File.expand_path("../../.henitai.yml", __dir__) }
  let(:schema) { JSON.parse(File.read(schema_path)) }
  let(:properties) { schema.fetch("properties") }

  it "disallows unknown top-level keys" do
    expect(schema.fetch("additionalProperties")).to be(false)
  end

  it "documents the supported top-level keys" do
    expect(properties.keys).to include(
      "integration",
      "includes",
      "mutation",
      "coverage_criteria",
      "thresholds",
      "reporters",
      "reports_dir",
      "dashboard",
      "jobs"
    )
  end

  it "documents the mutation operator set" do
    expect(properties.fetch("mutation").fetch("properties").fetch("operators").fetch("enum")).to eq(
      %w[light full]
    )
  end

  it "documents sampling as a complete configuration block" do
    sampling = properties.fetch("mutation").fetch("properties").fetch("sampling")

    expect(sampling.fetch("required")).to eq(%w[ratio strategy])
  end

  it "documents the sampling keys" do
    sampling = properties.fetch("mutation").fetch("properties").fetch("sampling")

    expect(sampling.fetch("properties").keys).to eq(%w[ratio strategy])
  end

  it "documents the coverage criteria keys" do
    expect(properties.fetch("coverage_criteria").fetch("properties").keys).to eq(
      %w[test_result timeout process_abort]
    )
  end

  it "keeps the sample config within the documented schema" do
    config = YAML.safe_load_file(sample_config_path, symbolize_names: true)

    expect(config.keys - Henitai::ConfigurationValidator::VALID_TOP_LEVEL_KEYS).to be_empty
  end
end
# rubocop:enable RSpec/DescribeClass
