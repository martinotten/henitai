# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ProcessWorkerRunner do
  # Minimal mutant-like double
  def build_mutant(id)
    subject = Struct.new(:expression).new("Foo##{id}")
    Struct.new(:id, :subject, :status) do
      def pending? = status == :pending
    end.new(id, subject, :pending)
  end

  # An integration stub that forks a real child process and returns results
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def build_integration(results_map)
    integration = instance_double(Henitai::Integration::Rspec)

    allow(integration).to receive(:select_tests) { |subject|
      ["spec/#{subject.expression}_spec.rb"]
    }

    allow(integration).to receive(:spawn_mutant) do |mutant:, **|
      log_paths = {
        stdout_path: "/dev/null",
        stderr_path: "/dev/null",
        log_path: "/dev/null"
      }
      pid = Process.fork do
        # Simulate some work; exit 0 = survived (success? is true)
        sleep(results_map.fetch(mutant.id, {}).fetch(:sleep, 0))
        exit_code = results_map.fetch(mutant.id, {}).fetch(:exit_code, 0)
        Process.exit(exit_code)
      end
      Henitai::Integration::ChildHandle.new(pid, log_paths)
    end

    allow(integration).to receive(:build_result) do |wait_result, log_paths|
      Henitai::ScenarioExecutionResult.build(
        wait_result: wait_result,
        stdout: "",
        stderr: "",
        log_path: log_paths[:log_path]
      )
    end

    integration
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  describe "empty queue" do
    it "returns empty array immediately when given zero mutants" do
      runner = described_class.new(worker_count: 2)
      integration = instance_double(Henitai::Integration::Rspec)
      config = Struct.new(:timeout).new(10.0)

      results = runner.run([], integration, config, nil)

      expect(results).to eq([])
    end
  end

  describe "basic dispatch" do
    it "runs all mutants to completion and returns results" do # rubocop:disable RSpec/MultipleExpectations
      mutant_a = build_mutant("a")
      mutant_b = build_mutant("b")
      integration = build_integration("a" => { exit_code: 1 }, "b" => { exit_code: 0 })
      config = Struct.new(:timeout).new(10.0)
      runner = described_class.new(worker_count: 2)

      results = runner.run([mutant_a, mutant_b], integration, config, nil)

      expect(results.size).to eq(2)
      statuses = results.map(&:status)
      expect(statuses).to include(:killed, :survived)
    end
  end

  describe "slot count" do
    it "runs mutants one at a time with jobs:1" do # rubocop:disable RSpec/MultipleExpectations
      mutant_a = build_mutant("a")
      mutant_b = build_mutant("b")
      started_at = {}

      integration = instance_double(Henitai::Integration::Rspec)
      allow(integration).to receive(:select_tests).and_return([])
      allow(integration).to receive(:spawn_mutant) do |mutant:, **|
        log_paths = { stdout_path: "/dev/null", stderr_path: "/dev/null",
                      log_path: "/dev/null" }
        started_at[mutant.id] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        pid = Process.fork do
          sleep(0.05)
          Process.exit(0)
        end
        Henitai::Integration::ChildHandle.new(pid, log_paths)
      end
      allow(integration).to receive(:build_result) do |wait_result, log_paths|
        Henitai::ScenarioExecutionResult.build(
          wait_result: wait_result, stdout: "", stderr: "",
          log_path: log_paths[:log_path]
        )
      end

      config = Struct.new(:timeout).new(10.0)
      runner = described_class.new(worker_count: 1)

      results = runner.run([mutant_a, mutant_b], integration, config, nil)

      expect(results.size).to eq(2)
      # With 1 slot, the second mutant starts after the first finishes.
      # started_at[b] must be >= started_at[a] + ~0.05s gap
      expect(started_at["b"]).to be >= started_at["a"] + 0.04
    end
  end

  describe "concurrency proof" do
    it "runs 4 mutants concurrently with real PID overlap" do # rubocop:disable RSpec/MultipleExpectations
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("HENITAI_DEBUG_SCHEDULER").and_return("1")
      Henitai::Integration::SchedulerDiagnostics.reset!

      mutants = (1..4).map { |i| build_mutant("m#{i}") }
      # Each mutant sleeps 0.3s; serial would take 1.2s
      results_map = (1..4).to_h { |i| ["m#{i}", { sleep: 0.3, exit_code: 0 }] }
      integration = build_integration(results_map)
      config = Struct.new(:timeout).new(5.0)
      runner = described_class.new(worker_count: 4)

      results = runner.run(mutants, integration, config, nil)

      expect(results.size).to eq(4)
      # Verify real OS-PID overlap: at least 2 children were live simultaneously
      expect(Henitai::Integration::SchedulerDiagnostics.summary[:max_concurrent]).to be >= 2
    end
  end

  describe "timeout isolation" do
    it "cleans up slots after timeout and leaves no active slots" do # rubocop:disable RSpec/MultipleExpectations
      mutant = build_mutant("slow")
      # Integration spawns a real child sleeping 10s but timeout is 0.1s
      integration = instance_double(Henitai::Integration::Rspec)
      allow(integration).to receive(:select_tests).and_return([])
      allow(integration).to receive(:spawn_mutant) do |**|
        log_paths = {
          stdout_path: "/dev/null",
          stderr_path: "/dev/null",
          log_path: "/dev/null"
        }
        pid = Process.fork do
          Process.setpgid(0, 0)
          sleep(10)
          Process.exit(0)
        end
        Henitai::Integration::ChildHandle.new(pid, log_paths)
      end
      allow(integration).to receive(:build_result) do |wait_result, log_paths|
        Henitai::ScenarioExecutionResult.build(
          wait_result: wait_result,
          stdout: "",
          stderr: "",
          log_path: log_paths[:log_path]
        )
      end
      config = Struct.new(:timeout).new(0.1)
      runner = described_class.new(worker_count: 1)

      results = runner.run([mutant], integration, config, nil)

      # Run must not hang and all children must be reaped
      expect(results.size).to eq(1)
      expect(results.first.status).to eq(:timeout)
      expect { Process.wait(-1, Process::WNOHANG) }.to raise_error(Errno::ECHILD)
    end
  end

  describe "interrupt semantics", pending: "PR 6 — interrupt handling" do
    it "marks active slots as :interrupted and raises Interrupt after cleanup"
  end

  describe "spawn failure isolation", pending: "PR 6 — fault isolation" do
    it "does not crash other slots when one fork fails"
  end

  describe "retry correctness", pending: "PR 6 — in-slot retry" do
    it "retries within the same slot when retries remain"
  end
end
