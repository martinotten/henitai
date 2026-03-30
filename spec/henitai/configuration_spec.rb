# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Configuration do
  def load_configuration(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".henitai.yml")
      File.write(path, yaml)
      described_class.load(path:)
    end
  end

  def load_configuration_with_overrides(yaml, overrides:)
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".henitai.yml")
      File.write(path, yaml)
      described_class.load(path:, overrides:)
    end
  end

  def configuration_snapshot(config)
    {
      integration: config.integration,
      operators: config.operators,
      jobs: config.jobs,
      timeout: config.timeout,
      coverage_criteria: config.coverage_criteria,
      thresholds: config.thresholds
    }
  end

  def expected_snapshot
    {
      integration: "rspec",
      operators: :light,
      jobs: nil,
      timeout: 12.5,
      coverage_criteria: {
        test_result: false,
        timeout: false,
        process_abort: false
      },
      thresholds: {
        high: 90,
        low: 60
      }
    }
  end

  def overridden_snapshot
    {
      integration: "minitest",
      operators: :full,
      jobs: 4,
      timeout: 5.0,
      coverage_criteria: {
        test_result: false,
        timeout: true,
        process_abort: false
      },
      thresholds: {
        high: 95,
        low: 75
      }
    }
  end

  it "merges partial nested config hashes with defaults" do
    expect(configuration_snapshot(load_configuration(<<~YAML))).to eq(expected_snapshot)
      mutation:
        timeout: 12.5
      coverage_criteria:
        test_result: false
      thresholds:
        high: 90
    YAML
  end

  it "applies CLI overrides after YAML values" do
    expect(
      configuration_snapshot(
        load_configuration_with_overrides(
          <<~YAML,
            integration:
              name: rspec
            jobs: 2
            mutation:
              operators: light
              timeout: 12.5
            coverage_criteria:
              test_result: false
            thresholds:
              high: 90
              low: 60
          YAML
          overrides: {
            integration: "minitest",
            jobs: 4,
            mutation: {
              operators: :full,
              timeout: 5.0
            },
            coverage_criteria: {
              timeout: true
            },
            thresholds: {
              high: 95,
              low: 75
            }
          }
        )
      )
    ).to eq(overridden_snapshot)
  end
end
