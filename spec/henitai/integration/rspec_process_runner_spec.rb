# frozen_string_literal: true

require "fileutils"
require "spec_helper"

RSpec.describe Henitai::Integration::RspecProcessRunner do
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists
  def build_integration
    instance_double(
      Henitai::Integration::Rspec,
      run_in_child: 7,
      wait_with_timeout: nil,
      build_result: nil,
      spawn_mutant: nil,
      spawn_suite_process: 4321,
      cleanup_process_group: nil,
      reap_child: nil
    )
  end

  def mutant_input
    Struct.new(:id).new("abc")
  end

  def successful_wait_status
    Struct.new(:success?, :exitstatus).new(true, 0)
  end

  def mutant_log_paths
    {
      stdout_path: "reports/mutation-logs/mutant-abc.stdout.log",
      stderr_path: "reports/mutation-logs/mutant-abc.stderr.log",
      log_path: "reports/mutation-logs/mutant-abc.log"
    }
  end

  def baseline_log_paths
    {
      stdout_path: "reports/mutation-logs/baseline.stdout.log",
      stderr_path: "reports/mutation-logs/baseline.stderr.log",
      log_path: "reports/mutation-logs/baseline.log"
    }
  end

  def stub_mutant_run(calls, integration, log_paths, pid:, wait_result:, build_result:)
    child_handle = Henitai::Integration::ChildHandle.new(
      pid:,
      log_paths:
    )

    allow(integration).to receive(:spawn_mutant) do |mutant:, test_files:|
      calls << [:spawn_mutant, mutant.id, test_files]
      child_handle
    end
    allow(integration).to receive(:wait_with_timeout) do |wait_pid, timeout|
      calls << [:wait_with_timeout, wait_pid, timeout]
      wait_result
    end
    allow(integration).to receive(:build_result) do |status, paths|
      calls << [:build_result, status, paths]
      build_result
    end
    allow(integration).to receive(:cleanup_process_group) do |child_pid|
      calls << [:cleanup, child_pid]
    end
    allow(integration).to receive(:reap_child) do |child_pid|
      calls << [:reap, child_pid]
    end
  end

  def stub_suite_run(calls, integration, log_paths, pid:, wait_result:, build_result:)
    allow(integration).to receive(:scenario_log_paths) do |name|
      calls << [:scenario_log_paths, name]
      log_paths
    end
    allow(FileUtils).to receive(:mkdir_p) do |path|
      calls << [:mkdir_p, path]
    end
    allow(integration).to receive(:spawn_suite_process) do |test_files, log_paths|
      calls << [:spawn_suite_process, test_files, log_paths]
      pid
    end
    allow(integration).to receive(:wait_with_timeout) do |wait_pid, timeout|
      calls << [:wait_with_timeout, wait_pid, timeout]
      wait_result
    end
    allow(integration).to receive(:build_result) do |status, log_paths|
      calls << [:build_result, status, log_paths]
      build_result
    end
    allow(integration).to receive(:cleanup_process_group) do |child_pid|
      calls << [:cleanup, child_pid]
    end
    allow(integration).to receive(:reap_child) do |child_pid|
      calls << [:reap, child_pid]
    end
  end

  it "runs a mutant via integration.spawn_mutant and finalizes the result" do
    integration = build_integration
    mutant = mutant_input
    wait_status = successful_wait_status
    log_paths = mutant_log_paths
    calls = []

    stub_mutant_run(
      calls,
      integration,
      log_paths,
      pid: 4_321,
      wait_result: wait_status,
      build_result: :result
    )

    result = described_class.new.run_mutant(
      integration,
      mutant:,
      test_files: ["spec/foo_spec.rb"],
      timeout: 1.5
    )

    expect([result, normalized_calls(calls)]).to eq(
      [:result, normalized_calls(mutant_run_calls(mutant, wait_status, log_paths))]
    )
  end

  it "spawns the suite in a fresh process group and cleans up on timeout" do
    integration = build_integration
    log_paths = baseline_log_paths
    calls = []

    stub_suite_run(
      calls,
      integration,
      log_paths,
      pid: 4_321,
      wait_result: :timeout,
      build_result: :timeout
    )

    result = described_class.new.run_suite(integration, ["spec/foo_spec.rb"], timeout: 12.5)

    expect([result, normalized_calls(calls)]).to eq(
      [:timeout, normalized_calls(baseline_timeout_calls(log_paths))]
    )
  end

  it "reaps the suite child when the wait result is nil" do
    integration = build_integration
    log_paths = baseline_log_paths
    calls = []

    stub_suite_run(
      calls,
      integration,
      log_paths,
      pid: 4_321,
      wait_result: nil,
      build_result: :survived
    )

    result = described_class.new.run_suite(integration, ["spec/foo_spec.rb"], timeout: 12.5)

    expect([result, calls.last(2)]).to eq(
      [:survived, [[:cleanup, 4_321], [:reap, 4_321]]]
    )
  end

  it "skips suite cleanup when no pid is returned" do
    integration = build_integration
    log_paths = baseline_log_paths
    calls = []

    stub_suite_run(
      calls,
      integration,
      log_paths,
      pid: nil,
      wait_result: nil,
      build_result: :survived
    )

    result = described_class.new.run_suite(integration, ["spec/foo_spec.rb"], timeout: 12.5)

    expect([result, normalized_calls(calls)]).to eq(
      [:survived, normalized_calls(baseline_nil_pid_calls(log_paths))]
    )
  end

  it "finalize skips cleanup when pid is nil" do
    integration = build_integration
    mutant = mutant_input
    log_paths = mutant_log_paths
    calls = []

    child_handle = Henitai::Integration::ChildHandle.new(
      pid: nil,
      log_paths:
    )

    allow(integration).to receive_messages(
      spawn_mutant: child_handle,
      wait_with_timeout: :survived,
      build_result: :survived
    )
    allow(integration).to receive(:cleanup_process_group) { |pid| calls << [:cleanup, pid] }
    allow(integration).to receive(:reap_child) { |pid| calls << [:reap, pid] }

    result = described_class.new.run_mutant(
      integration,
      mutant:,
      test_files: [],
      timeout: 1.0
    )

    expect([result, calls]).to eq([:survived, []])
  end

  def mutant_run_calls(mutant, wait_status, log_paths)
    [
      [:spawn_mutant, mutant.id, ["spec/foo_spec.rb"]],
      [:wait_with_timeout, 4_321, 1.5],
      [:build_result, wait_status, log_paths],
      [:cleanup, 4_321]
    ]
  end

  def baseline_timeout_calls(log_paths)
    [
      [:scenario_log_paths, "baseline"],
      [:mkdir_p, "reports/mutation-logs"],
      [:spawn_suite_process, ["spec/foo_spec.rb"], log_paths],
      [:wait_with_timeout, 4_321, 12.5],
      [:build_result, :timeout, log_paths]
    ]
  end

  def baseline_reap_calls(log_paths)
    baseline_timeout_calls(log_paths) + [[:cleanup, 4_321], [:reap, 4_321]]
  end

  def baseline_nil_pid_calls(log_paths)
    [
      [:scenario_log_paths, "baseline"],
      [:mkdir_p, "reports/mutation-logs"],
      [:spawn_suite_process, ["spec/foo_spec.rb"], log_paths],
      [:wait_with_timeout, nil, 12.5],
      [:build_result, nil, log_paths]
    ]
  end

  def normalized_calls(calls)
    calls.map { |entry| normalize_call(entry) }
  end

  def normalize_call(entry)
    return entry unless entry.is_a?(Array)

    entry.map do |value|
      value.is_a?(Hash) ? value.to_a.sort : value
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists
end
