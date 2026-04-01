# frozen_string_literal: true

require "spec_helper"

IntegrationSpy = Class.new do
  attr_reader :calls

  def initialize
    @calls = Hash.new(0)
  end

  def select_tests(subject)
    @calls[:select_tests] += 1
    @calls[:last_subject] = subject.expression
    ["spec/foo_spec.rb"]
  end

  def run_mutant(mutant:, test_files:, timeout:)
    @calls[:run_mutant] += 1
    @calls[:last_test_files] = test_files
    @calls[:last_timeout] = timeout
    mutant.status = :killed
  end
end

RSpec.describe Henitai::ExecutionEngine do
  def build_subject(expression)
    Struct.new(:expression).new(expression)
  end

  def build_mutant(status, expression)
    Struct.new(:status, :subject) do
      def pending?
        status == :pending
      end
    end.new(status, build_subject(expression))
  end

  def build_integration
    IntegrationSpy.new
  end

  def build_config
    Struct.new(:timeout, :reports_dir).new(12.5, "coverage")
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

  it "runs only pending mutants" do
    pending = build_mutant(:pending, "Foo#bar")
    ignored = build_mutant(:ignored, "Foo#baz")
    integration = build_integration

    described_class.new.run([pending, ignored], integration, build_config)

    expect(integration.calls.slice(:select_tests, :run_mutant)).to eq(
      select_tests: 1,
      run_mutant: 1
    )
  end

  it "updates pending mutant statuses from the integration result" do
    pending = build_mutant(:pending, "Foo#bar")
    ignored = build_mutant(:ignored, "Foo#baz")
    integration = build_integration

    result = described_class.new.run([pending, ignored], integration, build_config)

    expect(result.map(&:status)).to eq(%i[killed ignored])
  end

  it "reports progress for pending mutants when a reporter is provided" do
    pending = build_mutant(:pending, "Foo#bar")
    skipped = build_mutant(:ignored, "Foo#baz")
    integration = build_integration
    progress = Struct.new(:calls) do
      def progress(mutant)
        calls << mutant.status
      end
    end.new([])

    described_class.new.run([pending, skipped], integration, build_config, progress_reporter: progress)

    expect(progress.calls).to eq([:killed])
  end

  it "exposes the configured reports dir to the integration run" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir).new(12.5, "artifacts")
    observed_reports_dir = nil

    allow(integration).to receive(:run_mutant) do |mutant:, **_kwargs|
      observed_reports_dir = ENV.fetch("HENITAI_REPORTS_DIR", nil)
      mutant.status = :killed
    end

    described_class.new.run([pending], integration, config)

    expect(observed_reports_dir).to eq("artifacts")
  end

  it "restores the reports dir environment variable after execution" do
    pending = build_mutant(:pending, "Foo#bar")
    integration = build_integration
    config = Struct.new(:timeout, :reports_dir).new(12.5, "artifacts")

    with_env("HENITAI_REPORTS_DIR", "preexisting") do
      described_class.new.run([pending], integration, config)

      expect(ENV.fetch("HENITAI_REPORTS_DIR", nil)).to eq("preexisting")
    end
  end
end
