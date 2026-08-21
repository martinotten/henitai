# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Henitai::Configuration do
  def load_configuration(yaml, fixtures: [])
    Dir.mktmpdir do |dir|
      fixtures.each do |entry|
        target = File.join(dir, entry)
        entry.end_with?("/") ? FileUtils.mkdir_p(target) : FileUtils.touch(target)
      end
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
      reports_dir: config.reports_dir,
      all_logs: config.all_logs,
      timeout: config.timeout,
      max_flaky_retries: config.max_flaky_retries,
      sampling: config.sampling,
      coverage_criteria: config.coverage_criteria,
      thresholds: config.thresholds
    }
  end

  def expected_snapshot
    shared_snapshot.merge(
      timeout: 12.5,
      coverage_criteria: {
        test_result: false,
        timeout: true,
        process_abort: true
      },
      thresholds: {
        high: 90,
        low: 60
      }
    )
  end

  def overridden_snapshot
    shared_snapshot.merge(
      integration: "minitest",
      operators: :full,
      jobs: 4,
      timeout: 5.0,
      coverage_criteria: {
        test_result: false,
        timeout: true,
        process_abort: true
      },
      thresholds: {
        high: 95,
        low: 75
      }
    )
  end

  def shared_snapshot
    {
      integration: "rspec",
      operators: :light,
      jobs: 1,
      reports_dir: "reports",
      all_logs: false,
      max_flaky_retries: 3,
      sampling: nil
    }
  end

  describe "timeout calibration settings" do
    it "reports the timeout as configured when mutation.timeout is set" do
      config = load_configuration(<<~YAML)
        mutation:
          timeout: 12.5
      YAML

      expect(config.timeout_configured?).to be(true)
    end

    it "reports the timeout as unconfigured by default" do
      expect(load_configuration("{}").timeout_configured?).to be(false)
    end

    it "defaults the timeout multiplier" do
      expect(load_configuration("{}").timeout_multiplier).to eq(
        described_class::DEFAULT_TIMEOUT_MULTIPLIER
      )
    end

    it "reads the timeout multiplier from the mutation block" do
      config = load_configuration(<<~YAML)
        mutation:
          timeout_multiplier: 5.0
      YAML

      expect(config.timeout_multiplier).to eq(5.0)
    end
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

  it "defaults the integration name when the integration hash omits it" do
    config = load_configuration(<<~YAML)
      integration: {}
    YAML

    expect(config.integration).to eq("rspec")
  end

  context "when no integration is configured" do
    it "detects minitest when a test/ directory is present" do
      config = load_configuration("", fixtures: ["test/"])
      expect(config.integration).to eq("minitest")
    end

    it "detects rspec when a spec/ directory is present" do
      config = load_configuration("", fixtures: ["spec/"])
      expect(config.integration).to eq("rspec")
    end

    it "detects rspec when a .rspec file is present" do
      config = load_configuration("", fixtures: [".rspec"])
      expect(config.integration).to eq("rspec")
    end

    it "prefers .rspec over test/ when both are present" do
      config = load_configuration("", fixtures: [".rspec", "test/"])
      expect(config.integration).to eq("rspec")
    end

    it "defaults to rspec when no detection signals are present" do
      config = load_configuration("")
      expect(config.integration).to eq("rspec")
    end
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
      jobs: 1,
      reports_dir: "reports",
      all_logs: false,
      timeout: 10.0,
      max_flaky_retries: 3,
      sampling: nil,
      coverage_criteria: {
        test_result: true,
        timeout: true,
        process_abort: true
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
      jobs: 1,
      reports_dir: "reports",
      all_logs: false,
      timeout: 10.0,
      max_flaky_retries: 3,
      sampling: nil,
      coverage_criteria: {
        test_result: true,
        timeout: true,
        process_abort: true
      },
      thresholds: {
        high: 80,
        low: 60
      }
    )
  end

  it "reports the root value type when configuration is not a mapping" do
    expect { load_configuration("- item\n") }
      .to raise_error(
        Henitai::ConfigurationError,
        /configuration: expected Hash, got Array/
      )
  end

  it "warns on unknown keys and still loads the known ones" do
    allow(Henitai::ConfigurationValidator).to receive(:warn)

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

    expect(Henitai::ConfigurationValidator).to have_received(:warn)
      .with(/Unknown configuration key/).at_least(:once)
  end

  it "loads a custom reports directory" do
    config = load_configuration(<<~YAML)
      reports_dir: custom-reports
    YAML

    expect(config.reports_dir).to eq("custom-reports")
  end

  it "defaults test_excludes to an empty array" do
    config = load_configuration("integration:\n  name: rspec\n")

    expect(config.test_excludes).to eq([])
  end

  it "defaults includes to the lib directory" do
    config = load_configuration("integration:\n  name: rspec\n")

    expect(config.includes).to eq(["lib"])
  end

  it "defaults reporters to the terminal reporter" do
    config = load_configuration("integration:\n  name: rspec\n")

    expect(config.reporters).to eq(["terminal"])
  end

  it "loads test_excludes globs" do
    config = load_configuration(<<~YAML)
      test_excludes:
        - spec/henitai/cli_spec.rb
        - spec/henitai/integration/*_spec.rb
    YAML

    expect(config.test_excludes).to eq(["spec/henitai/cli_spec.rb", "spec/henitai/integration/*_spec.rb"])
  end

  it "aborts on a non-array test_excludes" do
    expect do
      load_configuration("test_excludes: nope\n")
    end.to raise_error(Henitai::ConfigurationError, /test_excludes/)
  end

  it "loads the all_logs flag" do
    config = load_configuration(<<~YAML)
      all_logs: true
    YAML

    expect(config.all_logs).to be(true)
  end

  it "defaults the output cap and calibrated-timeout ceiling", :aggregate_failures do
    config = load_configuration("integration:\n  name: rspec\n")

    expect(config.max_log_bytes).to eq(described_class::DEFAULT_MAX_LOG_BYTES)
    expect(config.max_timeout).to eq(described_class::DEFAULT_MAX_TIMEOUT)
  end

  it "loads a custom output cap and timeout ceiling", :aggregate_failures do
    config = load_configuration(<<~YAML)
      mutation:
        max_log_bytes: 1048576
        max_timeout: 15
    YAML

    expect(config.max_log_bytes).to eq(1_048_576)
    expect(config.max_timeout).to eq(15)
  end

  it "defaults the checkpoint settings", :aggregate_failures do
    config = load_configuration("integration:\n  name: rspec\n")

    expect(config.checkpoint_enabled).to be(true)
    expect(config.checkpoint_every).to eq(described_class::DEFAULT_CHECKPOINT_EVERY)
    expect(config.checkpoint_interval).to eq(described_class::DEFAULT_CHECKPOINT_INTERVAL)
  end

  it "loads custom checkpoint settings", :aggregate_failures do
    config = load_configuration(<<~YAML)
      reports:
        checkpoint: false
        checkpoint_every: 50
        checkpoint_interval: 10
    YAML

    expect(config.checkpoint_enabled).to be(false)
    expect(config.checkpoint_every).to eq(50)
    expect(config.checkpoint_interval).to eq(10)
  end

  it "aborts on a non-positive max_log_bytes" do
    expect do
      load_configuration("mutation:\n  max_log_bytes: -1\n")
    end.to raise_error(Henitai::ConfigurationError, /mutation\.max_log_bytes/)
  end

  it "aborts when max_log_bytes is zero" do
    expect do
      load_configuration("mutation:\n  max_log_bytes: 0\n")
    end.to raise_error(Henitai::ConfigurationError, /mutation\.max_log_bytes/)
  end

  it "aborts on a non-positive max_timeout" do
    expect do
      load_configuration("mutation:\n  max_timeout: 0\n")
    end.to raise_error(Henitai::ConfigurationError, /mutation\.max_timeout/)
  end

  it "aborts on a non-positive checkpoint_every" do
    expect do
      load_configuration("reports:\n  checkpoint_every: 0\n")
    end.to raise_error(Henitai::ConfigurationError, /reports\.checkpoint_every/)
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

  it "aborts on invalid report directory types" do
    expect do
      load_configuration(<<~YAML)
        reports_dir: 123
      YAML
    end.to raise_error(
      Henitai::ConfigurationError,
      /reports_dir/
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

  it "aborts on invalid max flaky retry values" do
    expect do
      load_configuration(<<~YAML)
        mutation:
          max_flaky_retries: -1
      YAML
    end.to raise_error(
      Henitai::ConfigurationError,
      /mutation\.max_flaky_retries/
    )
  end

  it "aborts on invalid sampling settings" do
    expect do
      load_configuration(<<~YAML)
        mutation:
          sampling:
            ratio: 1.5
            strategy: random
      YAML
    end.to raise_error(
      Henitai::ConfigurationError,
      /mutation\.sampling/
    )
  end

  it "aborts on non-symbolizable sampling strategy values" do
    expect do
      load_configuration(<<~YAML)
        mutation:
          sampling:
            ratio: 0.5
            strategy: 123
      YAML
    end.to raise_error(
      Henitai::ConfigurationError,
      /mutation\.sampling\.strategy/
    )
  end

  it "aborts on incomplete sampling settings" do
    expect do
      load_configuration(<<~YAML)
        mutation:
          sampling:
            strategy: stratified
      YAML
    end.to raise_error(
      Henitai::ConfigurationError,
      /mutation\.sampling/
    )
  end

  it "aborts on incomplete sampling settings without a strategy" do
    expect do
      load_configuration(<<~YAML)
        mutation:
          sampling:
            ratio: 0.5
      YAML
    end.to raise_error(
      Henitai::ConfigurationError,
      /mutation\.sampling/
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

  it "symbolizes string-keyed overrides recursively" do
    config = load_configuration_with_overrides(
      <<~YAML,
        mutation:
          operators: light
      YAML
      overrides: {
        "integration" => {
          "name" => "minitest"
        },
        "mutation" => {
          "operators" => "full",
          "sampling" => {
            "ratio" => 0.25,
            "strategy" => "stratified"
          }
        }
      }
    )

    expect(
      {
        integration: config.integration,
        operators: config.operators,
        sampling: config.sampling
      }
    ).to eq(
      integration: "minitest",
      operators: :full,
      sampling: {
        ratio: 0.25,
        strategy: "stratified"
      }
    )
  end

  it "loads sampling settings" do
    config = load_configuration(<<~YAML)
      mutation:
        max_flaky_retries: 4
        sampling:
          ratio: 0.25
          strategy: stratified
    YAML

    expect(
      {
        max_flaky_retries: config.max_flaky_retries,
        sampling: config.sampling
      }
    ).to eq(
      max_flaky_retries: 4,
      sampling: {
        ratio: 0.25,
        strategy: "stratified"
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

  it "defaults excludes to an empty array" do
    expect(load_missing_configuration.excludes).to eq([])
  end

  it "loads excludes as a string array" do
    config = load_configuration(<<~YAML)
      excludes:
        - lib/henitai/eager_load.rb
    YAML

    expect(config.excludes).to eq(["lib/henitai/eager_load.rb"])
  end

  it "aborts on invalid excludes values" do
    expect do
      load_configuration(<<~YAML)
        excludes: lib/henitai/eager_load.rb
      YAML
    end.to raise_error(
      Henitai::ConfigurationError,
      /excludes: expected Array<String>, got String/
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

  it "aborts on invalid ignore pattern regexes" do
    expect do
      load_configuration(<<~YAML)
        mutation:
          ignore_patterns:
            - "("
      YAML
    end.to raise_error(
      Henitai::ConfigurationError,
      /mutation\.ignore_patterns: invalid regular expression/
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
