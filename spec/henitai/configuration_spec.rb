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

  def load_missing_configuration
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".henitai.yml")
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

  it "loads defaults when the configuration file is missing" do
    expect(configuration_snapshot(load_missing_configuration)).to eq(
      integration: "rspec",
      operators: :light,
      jobs: nil,
      timeout: 10.0,
      coverage_criteria: {
        test_result: true,
        timeout: false,
        process_abort: false
      },
      thresholds: {
        high: 80,
        low: 60
      }
    )
  end

  it "loads defaults when the configuration file is empty" do
    expect(configuration_snapshot(load_configuration(""))).to eq(
      integration: "rspec",
      operators: :light,
      jobs: nil,
      timeout: 10.0,
      coverage_criteria: {
        test_result: true,
        timeout: false,
        process_abort: false
      },
      thresholds: {
        high: 80,
        low: 60
      }
    )
  end

  it "warns on unknown keys and still loads the known ones" do
    expect do
      load_configuration(<<~YAML)
        integration:
          name: rspec
        dashboard:
          project: example/repo
          unknown_flag: true
        mutation:
          timeout: 12.5
          unknown_flag: true
        unknown_top_level: yes
      YAML
    end.to output(/Unknown configuration key/).to_stderr
  end

  it "aborts on invalid mutation operators" do
    expect do
      load_configuration(<<~YAML)
        mutation:
          operators: turbo
      YAML
    end.to raise_error(
      Henitai::ConfigurationError,
      /mutation\.operators/
    )
  end

  it "aborts on invalid mutation operator types" do
    expect do
      load_configuration(<<~YAML)
        mutation:
          operators: 123
      YAML
    end.to raise_error(
      Henitai::ConfigurationError,
      /mutation\.operators/
    )
  end

  it "loads dashboard settings and array overrides" do
    config = load_configuration_with_overrides(
      <<~YAML,
        dashboard:
          project: example/repo
          base_url: https://dashboard.example.test
        mutation:
          ignore_patterns:
            - "(send _ :puts _)"
        reporters:
          - terminal
      YAML
      overrides: {
        includes: ["app"],
        reporters: ["json"],
        mutation: {
          ignore_patterns: ["(send _ :warn _)"]
        }
      }
    )

    expect(
      {
        includes: config.includes,
        reporters: config.reporters,
        ignore_patterns: config.ignore_patterns,
        dashboard: config.dashboard
      }
    ).to eq(
      includes: ["app"],
      reporters: ["json"],
      ignore_patterns: ["(send _ :warn _)"],
      dashboard: {
        project: "example/repo",
        base_url: "https://dashboard.example.test"
      }
    )
  end

  it "aborts on invalid jobs values" do
    expect do
      load_configuration(<<~YAML)
        jobs: nope
      YAML
    end.to raise_error(Henitai::ConfigurationError, /jobs/)
  end

  it "aborts on invalid includes values" do
    expect do
      load_configuration(<<~YAML)
        includes: lib
      YAML
    end.to raise_error(
      Henitai::ConfigurationError,
      /includes: expected Array<String>, got String/
    )
  end

  it "describes invalid array element types" do
    expect do
      load_configuration(<<~YAML)
        mutation:
          ignore_patterns:
            - "(send _ :puts _)"
            - 1
      YAML
    end.to raise_error(
      Henitai::ConfigurationError,
      /mutation\.ignore_patterns: expected Array<String>, got Array<String, Integer>/
    )
  end

  it "aborts on invalid mutation timeout values" do
    expect do
      load_configuration(<<~YAML)
        mutation:
          timeout: soon
      YAML
    end.to raise_error(Henitai::ConfigurationError, /mutation\.timeout/)
  end

  it "aborts on invalid threshold values" do
    expect do
      load_configuration(<<~YAML)
        thresholds:
          high: 101
      YAML
    end.to raise_error(Henitai::ConfigurationError, /thresholds\.high/)
  end

  it "aborts on invalid coverage criteria values" do
    expect do
      load_configuration(<<~YAML)
        coverage_criteria:
          test_result: 1
      YAML
    end.to raise_error(
      Henitai::ConfigurationError,
      /coverage_criteria\.test_result/
    )
  end

  it "aborts on invalid dashboard values" do
    expect do
      load_configuration(<<~YAML)
        dashboard:
          project: 123
      YAML
    end.to raise_error(Henitai::ConfigurationError, /dashboard\.project/)
  end

  it "aborts when dashboard is not a hash" do
    expect do
      load_configuration(<<~YAML)
        dashboard: nope
      YAML
    end.to raise_error(Henitai::ConfigurationError, /dashboard/)
  end

  it "aborts on invalid top-level configuration shapes" do
    expect do
      load_configuration(<<~YAML)
        - bad
      YAML
    end.to raise_error(Henitai::ConfigurationError, /configuration/)
  end
end
