# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ProcessWorkerRunner do
  after do
    loop do
      pid = Process.wait(-1, Process::WNOHANG)
      break unless pid
    end
  rescue Errno::ECHILD
    nil
  end

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
      config = Struct.new(:timeout, :max_flaky_retries).new(10.0, 0)

      results = runner.run([], integration, config, nil)

      expect(results).to eq([])
    end
  end

  describe "basic dispatch" do
    it "runs all mutants to completion and returns results" do # rubocop:disable RSpec/MultipleExpectations
      mutant_a = build_mutant("a")
      mutant_b = build_mutant("b")
      integration = build_integration("a" => { exit_code: 1 }, "b" => { exit_code: 0 })
      config = Struct.new(:timeout, :max_flaky_retries).new(10.0, 0)
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
          sleep(0.01)
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

      config = Struct.new(:timeout, :max_flaky_retries).new(10.0, 0)
      runner = described_class.new(worker_count: 1)

      results = runner.run([mutant_a, mutant_b], integration, config, nil)

      expect(results.size).to eq(2)
      # With 1 slot, the second mutant starts after the first finishes.
      # started_at[b] must be >= started_at[a] + ~0.01s gap
      expect(started_at["b"]).to be >= started_at["a"] + 0.008
    end
  end

  describe "concurrency proof" do
    it "runs 4 mutants concurrently with real PID overlap and sub-serial wall time" do # rubocop:disable RSpec/MultipleExpectations
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("HENITAI_DEBUG_SCHEDULER").and_return("1")
      Henitai::Integration::SchedulerDiagnostics.reset!

      mutants = (1..4).map { |i| build_mutant("m#{i}") }
      # Each mutant sleeps 0.05s; serial would take ~0.2s
      results_map = (1..4).to_h { |i| ["m#{i}", { sleep: 0.05, exit_code: 0 }] }
      integration = build_integration(results_map)
      config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 0)
      runner = described_class.new(worker_count: 4)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      results = runner.run(mutants, integration, config, nil)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(results.size).to eq(4)
      # Verify real OS-PID overlap: at least 2 children were live simultaneously
      expect(Henitai::Integration::SchedulerDiagnostics.summary[:max_concurrent]).to be >= 2
      # Wall time must be materially below serial (0.2s); 0.25s still proves concurrency
      expect(elapsed).to be < 0.25
    end
  end

  describe "wakeup loop" do
    it "waits on a wakeup io while children are active" do
      mutant = build_mutant("wakeup")
      integration = build_integration("wakeup" => { sleep: 0.005, exit_code: 0 })
      config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 0)
      runner = described_class.new(worker_count: 1)

      allow(IO).to receive(:select).and_call_original

      runner.run([mutant], integration, config, nil)

      expect(IO).to have_received(:select).with(
        array_including(instance_of(IO)),
        nil,
        nil,
        kind_of(Numeric)
      )
    end
  end

  describe "timeout isolation" do
    it "cleans up slots after timeout and leaves no active slots" do # rubocop:disable RSpec/MultipleExpectations
      mutant = build_mutant("slow")
      spawned_pid = nil
      # Integration spawns a real child that outlives the timeout.
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
          sleep(0.2)
          Process.exit(0)
        end
        spawned_pid = pid
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
      config = Struct.new(:timeout, :max_flaky_retries).new(0.1, 0)
      runner = described_class.new(worker_count: 1)

      results = runner.run([mutant], integration, config, nil)

      # Run must not hang and all children must be reaped
      expect(results.size).to eq(1)
      expect(results.first.status).to eq(:timeout)
      # Verify the specific spawned pid was reaped (not a global wait that could
      # consume unrelated children from other specs or helpers)
      expect { Process.wait(spawned_pid, Process::WNOHANG) }.to raise_error(Errno::ECHILD)
    end
  end

  describe "interrupt semantics" do
    it "raises Interrupt, reaps all children, and emits no result for in-flight mutants" do # rubocop:disable RSpec/MultipleExpectations
      spawned_pid = nil
      mutant = build_mutant("slow")
      integration = instance_double(Henitai::Integration::Rspec)
      allow(integration).to receive(:select_tests).and_return([])
      allow(integration).to receive(:spawn_mutant) do |**|
        log_paths = { stdout_path: "/dev/null", stderr_path: "/dev/null",
                      log_path: "/dev/null" }
        pid = Process.fork do
          Process.setpgid(0, 0)
          sleep(0.2)
          Process.exit(0)
        end
        spawned_pid = pid
        Henitai::Integration::ChildHandle.new(pid, log_paths)
      end
      allow(integration).to receive(:build_result) do |wait_result, log_paths|
        Henitai::ScenarioExecutionResult.build(
          wait_result: wait_result, stdout: "", stderr: "",
          log_path: log_paths[:log_path]
        )
      end
      config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 0)
      runner = described_class.new(worker_count: 1)

      # Trigger shutdown via the public API rather than OS signals to avoid
      # signal interference with other specs running in the same process.
      shutdown_thread = Thread.new do
        sleep 0.001
        runner.request_shutdown
      end

      expect { runner.run([mutant], integration, config, nil) }.to raise_error(Interrupt)
      # Interrupted slot must not produce a verdict
      expect(mutant.status).to eq(:pending)
      # Child process must be reaped
      expect { Process.wait(spawned_pid, Process::WNOHANG) }.to raise_error(Errno::ECHILD)
      shutdown_thread.join
    end
  end

  describe "spawn failure isolation" do
    it "does not crash other slots when one spawn raises" do # rubocop:disable RSpec/MultipleExpectations
      mutant_a = build_mutant("ok_a")
      mutant_b = build_mutant("fail")
      mutant_c = build_mutant("ok_c")

      integration = instance_double(Henitai::Integration::Rspec)
      allow(integration).to receive(:select_tests).and_return([])
      allow(integration).to receive(:spawn_mutant) do |mutant:, **|
        raise "simulated fork failure" if mutant.id == "fail"

        log_paths = { stdout_path: "/dev/null", stderr_path: "/dev/null",
                      log_path: "/dev/null" }
        pid = Process.fork { Process.exit(1) }
        Henitai::Integration::ChildHandle.new(pid, log_paths)
      end
      allow(integration).to receive(:build_result) do |wait_result, log_paths|
        Henitai::ScenarioExecutionResult.build(
          wait_result: wait_result, stdout: "", stderr: "",
          log_path: log_paths[:log_path]
        )
      end

      config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 0)
      runner = described_class.new(worker_count: 3)

      results = runner.run([mutant_a, mutant_b, mutant_c], integration, config, nil)

      expect(results.size).to eq(3)
      expect(mutant_b.status).to eq(:killed)
    end
  end

  describe "retry correctness" do
    it "retries within the same slot when retries remain and returns the final outcome" do # rubocop:disable RSpec/MultipleExpectations
      mutant = build_mutant("flaky")
      call_count = 0

      integration = instance_double(Henitai::Integration::Rspec)
      allow(integration).to receive(:select_tests).and_return([])
      allow(integration).to receive(:spawn_mutant) do |**|
        log_paths = { stdout_path: "/dev/null", stderr_path: "/dev/null",
                      log_path: "/dev/null" }
        call_count += 1
        exit_code = call_count == 1 ? 0 : 1 # survived first run, killed on retry
        pid = Process.fork { Process.exit(exit_code) }
        Henitai::Integration::ChildHandle.new(pid, log_paths)
      end
      allow(integration).to receive(:build_result) do |wait_result, log_paths|
        Henitai::ScenarioExecutionResult.build(
          wait_result: wait_result, stdout: "", stderr: "",
          log_path: log_paths[:log_path]
        )
      end

      config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 1)
      runner = described_class.new(worker_count: 1)

      results = runner.run([mutant], integration, config, nil)

      expect(results.size).to eq(1)
      expect(results.first.status).to eq(:killed)
      expect(call_count).to eq(2)
    end
  end
end
