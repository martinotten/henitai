# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::CoverageBootstrapper do
  def build_config
    Struct.new(:reports_dir).new("reports")
  end

  def with_env(key, value)
    original = ENV.fetch(key, nil)
    ENV[key] = value
    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end

  def build_integration(test_files:, run_suite_result:)
    instance_double(
      Henitai::Integration::Rspec,
      test_files: test_files,
      run_suite: run_suite_result
    )
  end

  it "sets a dedicated coverage dir while bootstrapping the suite" do
    static_filter = instance_double(Henitai::StaticFilter)
    integration = build_integration(
      test_files: ["spec/sample_spec.rb"],
      run_suite_result: :survived
    )

    bootstrapper = described_class.new(static_filter:)

    allow(static_filter).to receive(:coverage_lines_for).and_return(
      {},
      { File.expand_path("lib/sample.rb") => [2] }
    )
    allow(integration).to receive(:run_suite) do |_test_files|
      expect(
        ENV.fetch("HENITAI_COVERAGE_DIR", nil)
      ).to eq(
        File.join("reports", "coverage")
      )
      :survived
    end

    bootstrapper.ensure!(
      source_files: [File.expand_path("lib/sample.rb")],
      config: build_config,
      integration:
    )
  end

  it "runs the configured test suite when coverage is missing" do
    static_filter = instance_double(Henitai::StaticFilter)
    integration = build_integration(
      test_files: ["spec/sample_spec.rb"],
      run_suite_result: :survived
    )

    bootstrapper = described_class.new(static_filter:)

    allow(static_filter).to receive(:coverage_lines_for).and_return(
      {},
      { File.expand_path("lib/sample.rb") => [2] }
    )
    allow(integration).to receive(:run_suite).and_return(:survived)

    bootstrapper.ensure!(
      source_files: [File.expand_path("lib/sample.rb")],
      config: build_config,
      integration:
    )

    expect(integration).to have_received(:run_suite).with(["spec/sample_spec.rb"])
  end

  it "restores the coverage dir environment after bootstrapping" do
    static_filter = instance_double(Henitai::StaticFilter)
    integration = build_integration(
      test_files: ["spec/sample_spec.rb"],
      run_suite_result: :survived
    )

    bootstrapper = described_class.new(static_filter:)

    allow(static_filter).to receive(:coverage_lines_for).and_return(
      {},
      { File.expand_path("lib/sample.rb") => [2] }
    )

    with_env("HENITAI_COVERAGE_DIR", "preexisting") do
      bootstrapper.ensure!(
        source_files: [File.expand_path("lib/sample.rb")],
        config: build_config,
        integration:
      )

      expect(ENV.fetch("HENITAI_COVERAGE_DIR", nil)).to eq("preexisting")
    end
  end

  it "skips the bootstrap when coverage is already available" do
    static_filter = instance_double(Henitai::StaticFilter)
    integration = build_integration(
      test_files: ["spec/sample_spec.rb"],
      run_suite_result: :survived
    )

    bootstrapper = described_class.new(static_filter:)

    allow(static_filter).to receive(:coverage_lines_for).and_return(
      { File.expand_path("lib/sample.rb") => [2] }
    )

    bootstrapper.ensure!(
      source_files: [File.expand_path("lib/sample.rb")],
      config: build_config,
      integration:
    )

    expect(integration).not_to have_received(:run_suite)
  end

  it "raises when the coverage bootstrap still produces no usable coverage" do
    static_filter = instance_double(Henitai::StaticFilter)
    integration = build_integration(
      test_files: ["spec/sample_spec.rb"],
      run_suite_result: :survived
    )

    bootstrapper = described_class.new(static_filter:)

    allow(static_filter).to receive(:coverage_lines_for).and_return({}, {})
    allow(integration).to receive(:run_suite).and_return(:survived)

    expect do
      bootstrapper.ensure!(
        source_files: [File.expand_path("lib/sample.rb")],
        config: build_config,
        integration:
      )
    end.to raise_error(
      Henitai::CoverageError,
      /coverage/i
    )
  end
end
