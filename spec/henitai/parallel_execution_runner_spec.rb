# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ParallelExecutionRunner do
  def build_mutant(expression)
    Struct.new(:status, :subject, :covered_by, :tests_completed) do
      def pending?
        status == :pending
      end
    end.new(:pending, Struct.new(:expression).new(expression))
  end

  def build_fake_integration
    Class.new do
      define_method(:run_mutant) do |mutant:, **_kwargs|
        mutant.status = :killed
      end
    end.new
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

  it "emits scheduler diagnostics to stderr when HENITAI_DEBUG_SCHEDULER=1" do
    first = build_mutant("Foo#bar")
    second = build_mutant("Foo#baz")
    integration = build_fake_integration
    config = Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries).new(12.5, "coverage", 2, 0)

    process_mutant = lambda do |mutant, _integration, _config, _reporter, _mutex|
      integration.run_mutant(mutant:)
    end

    runner = described_class.new(worker_count: 2)
    context = runner.send(
      :build_parallel_context,
      [first, second],
      integration,
      config,
      nil
    )

    with_env("HENITAI_DEBUG_SCHEDULER", "1") do
      expect do
        runner.execute_parallel_execution(context, stdin_pipe: false, process_mutant: process_mutant)
      end.to output(/\[henitai-scheduler\] max_concurrent_children=\d+/).to_stderr
    end
  end

  it "emits child interval records to stderr when HENITAI_DEBUG_SCHEDULER=1" do
    first = build_mutant("Foo#bar")
    integration = build_fake_integration
    config = Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries).new(12.5, "coverage", 2, 0)

    process_mutant = lambda do |mutant, _integration, _config, _reporter, _mutex|
      integration.run_mutant(mutant:)
    end

    runner = described_class.new(worker_count: 1)
    context = runner.send(
      :build_parallel_context,
      [first],
      integration,
      config,
      nil
    )

    with_env("HENITAI_DEBUG_SCHEDULER", "1") do
      expect do
        runner.execute_parallel_execution(context, stdin_pipe: false, process_mutant: process_mutant)
      end.to output(/\[henitai-scheduler\] child_intervals=\[/).to_stderr
    end
  end

  it "does not emit diagnostics when HENITAI_DEBUG_SCHEDULER is not set" do
    first = build_mutant("Foo#bar")
    integration = build_fake_integration
    config = Struct.new(:timeout, :reports_dir, :jobs, :max_flaky_retries).new(12.5, "coverage", 2, 0)

    process_mutant = lambda do |mutant, _integration, _config, _reporter, _mutex|
      integration.run_mutant(mutant:)
    end

    runner = described_class.new(worker_count: 1)
    context = runner.send(
      :build_parallel_context,
      [first],
      integration,
      config,
      nil
    )

    expect do
      runner.execute_parallel_execution(context, stdin_pipe: false, process_mutant: process_mutant)
    end.not_to output.to_stderr
  end
end
