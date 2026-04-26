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
  def build_integration(results_map)
    integration = instance_double(Henitai::Integration::Rspec)

    allow(integration).to receive(:select_tests) { |subject|
      ["spec/#{subject.expression}_spec.rb"]
    }

    allow(integration).to receive(:spawn_mutant) do |mutant:, test_files:|
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
    it "runs all mutants to completion and returns results" do
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
    it "runs mutants one at a time with jobs:1" do
      mutant_a = build_mutant("a")
      mutant_b = build_mutant("b")
      started_at = {}

      integration = instance_double(Henitai::Integration::Rspec)
      allow(integration).to receive(:select_tests) { [] }
      allow(integration).to receive(:spawn_mutant) do |mutant:, test_files:|
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

  describe "concurrency proof", pending: "PR 5 — timeout and concurrency metrics" do
    it "runs 4 mutants concurrently and observes pid overlap > 1"
  end

  describe "timeout isolation", pending: "PR 5 — timeout handling" do
    it "cleans up slots after timeout and leaves no active slots"
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
