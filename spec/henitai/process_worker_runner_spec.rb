# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

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

  def build_wait_status(exitstatus)
    Struct.new(:exitstatus) do
      def success? = exitstatus.to_i.zero?

      def exited? = true
    end.new(exitstatus)
  end

  def build_fake_wakeup(on_wait: nil)
    state = { wait_calls: [], signal_count: 0, closed: false }
    wakeup = Object.new
    wakeup.define_singleton_method(:install) { self }
    wakeup.define_singleton_method(:wait) do |timeout|
      state[:wait_calls] << timeout
      on_wait&.call(timeout)
      [[], nil, nil]
    end
    wakeup.define_singleton_method(:drain) { nil }
    wakeup.define_singleton_method(:signal) { state[:signal_count] += 1 }
    wakeup.define_singleton_method(:close) { state[:closed] = true }
    [wakeup, state]
  end

  def build_fake_runtime(clock_times:, wait2_results:, wait_results: {}, traps: {})
    state = fake_runtime_state(clock_times, wait2_results, wait_results, traps)
    runtime = Object.new
    define_fake_runtime_methods(runtime, state)
    [runtime, state]
  end

  def fake_runtime_state(clock_times, wait2_results, wait_results, traps)
    {
      clock_times: clock_times.dup,
      wait2_results: wait2_results.transform_values(&:dup),
      wait_results: wait_results.dup,
      traps: traps,
      kill_calls: [],
      wait_calls: [],
      wait2_calls: []
    }
  end

  def define_fake_runtime_methods(runtime, state)
    define_fake_clock(runtime, state)
    define_fake_wait2(runtime, state)
    define_fake_kill(runtime, state)
    define_fake_wait(runtime, state)
    define_fake_trap(runtime, state)
  end

  def define_fake_clock(runtime, state)
    next_clock_time = -> { self.next_clock_time(state) }
    runtime.define_singleton_method(:clock_gettime) { |_clock_id| next_clock_time.call }
  end

  def define_fake_wait2(runtime, state)
    next_wait2_result = ->(pid, flags) { self.next_wait2_result(state, pid, flags) }
    runtime.define_singleton_method(:wait2) { |pid, flags = nil| next_wait2_result.call(pid, flags) }
  end

  def define_fake_kill(runtime, state)
    record_kill = ->(signal, pid) { self.record_kill(state, signal, pid) }
    runtime.define_singleton_method(:kill) { |signal, pid| record_kill.call(signal, pid) }
  end

  def define_fake_wait(runtime, state)
    record_wait = ->(pid) { self.record_wait(state, pid) }
    runtime.define_singleton_method(:wait) { |pid| record_wait.call(pid) }
  end

  def define_fake_trap(runtime, state)
    record_trap = ->(signal, handler, block) { self.record_trap(state, signal, handler, block) }
    runtime.define_singleton_method(:trap) do |signal, handler = nil, &block|
      record_trap.call(signal, handler, block)
    end
  end

  def next_clock_time(state)
    state[:clock_times].shift || state[:clock_times].last || 0.0
  end

  def next_wait2_result(state, pid, flags)
    state[:wait2_calls] << [pid, flags]
    results = state[:wait2_results].fetch(pid) { state[:wait2_results].fetch(:default, []) }
    results.empty? ? nil : results.shift
  end

  def record_kill(state, signal, pid)
    state[:kill_calls] << [signal, pid]
    1
  end

  def record_wait(state, pid)
    state[:wait_calls] << pid
    state[:wait_results][pid]
  end

  def record_trap(state, signal, handler, block)
    previous = state[:traps][signal]
    state[:traps][signal] = handler || block
    previous
  end

  def build_fake_handle(pid)
    Henitai::Integration::ChildHandle.new(
      pid,
      stdout_path: "/dev/null",
      stderr_path: "/dev/null",
      log_path: "/dev/null"
    )
  end

  def stub_fake_spawn(integration, pid)
    allow(integration).to receive_messages(
      select_tests: [],
      spawn_mutant: build_fake_handle(pid)
    )
  end

  def stub_fake_spawn_sequence(integration, sequence)
    values = sequence.dup
    allow(integration).to receive(:select_tests).and_return([])
    allow(integration).to receive(:spawn_mutant) do |**|
      value = values.shift
      raise value if value.is_a?(Exception)

      build_fake_handle(value)
    end
  end

  def build_fake_runner(worker_count:, wait2_results:)
    runtime, = build_fake_runtime(
      clock_times: Array.new(20, 0.0),
      wait2_results: { -1 => wait2_results }
    )
    wakeup, = build_fake_wakeup
    described_class.new(worker_count:, runtime:, wakeup:)
  end

  def stub_result_builder(integration)
    allow(integration).to receive(:build_result) do |wait_result, log_paths|
      Henitai::ScenarioExecutionResult.build(
        wait_result: wait_result,
        stdout: "",
        stderr: "",
        log_path: log_paths[:log_path]
      )
    end
  end

  describe "Runtime" do
    it "delegates wait2 to Process" do
      allow(Process).to receive(:wait2).and_return(:wait_result)

      result = described_class::Runtime.new.wait2(123, Process::WNOHANG)

      expect(result).to eq(:wait_result)
    end

    it "delegates wait to Process" do
      allow(Process).to receive(:wait) do |pid, _flags = nil|
        :wait_result if pid == 123
      end

      result = described_class::Runtime.new.wait(123)

      expect(result).to eq(:wait_result)
    end

    it "delegates kill to Process" do
      allow(Process).to receive(:kill).and_return(:sent)

      result = described_class::Runtime.new.kill("SIGTERM", 123)

      expect(result).to eq(:sent)
    end

    it "delegates trap to Kernel" do
      allow(Kernel).to receive(:trap).and_return(:previous)

      result = described_class::Runtime.new.trap("TERM", "DEFAULT")

      expect(result).to eq(:previous)
    end
  end

  describe "empty queue" do
    it "starts without a shutdown request" do
      runner = described_class.new(worker_count: 1)

      expect(runner.shutdown_requested?).to be(false)
    end

    it "reports zero flaky retries before a run starts" do
      runner = described_class.new(worker_count: 1)

      expect(runner.flaky_retry_count).to eq(0)
    end

    it "preserves diagnostics when debug mode is disabled" do
      diagnostics = Henitai::Integration::SchedulerDiagnostics
      diagnostics.reset!
      ENV["HENITAI_DEBUG_SCHEDULER"] = "1"
      diagnostics.child_started(123)
      ENV.delete("HENITAI_DEBUG_SCHEDULER")
      config = Struct.new(:timeout, :max_flaky_retries).new(10.0, 0)

      described_class.new(worker_count: 1).run(
        [],
        instance_double(Henitai::Integration::Rspec),
        config,
        nil
      )

      expect(diagnostics.summary.fetch(:intervals)).not_to be_empty
    ensure
      ENV.delete("HENITAI_DEBUG_SCHEDULER")
      Henitai::Integration::SchedulerDiagnostics.reset!
    end

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
      integration = instance_double(Henitai::Integration::Rspec)
      stub_fake_spawn_sequence(integration, [10, 11])
      stub_result_builder(integration)
      config = Struct.new(:timeout, :max_flaky_retries).new(10.0, 0)
      runner = build_fake_runner(
        worker_count: 2,
        wait2_results: [[10, build_wait_status(1)], [11, build_wait_status(0)]]
      )

      results = runner.run([mutant_a, mutant_b], integration, config, nil)

      expect(results.size).to eq(2)
      statuses = results.map(&:status)
      expect(statuses).to include(:killed, :survived)
    end
  end

  describe "slot count" do
    # Proves jobs:1 serialization deterministically via SchedulerDiagnostics
    # rather than a wall-clock gap: with one slot the runner must call
    # child_started/child_ended in matched pairs, so peak concurrency is 1.
    # If two children were ever live at once, max_concurrent would reach 2.
    it "runs mutants one at a time with jobs:1" do # rubocop:disable RSpec/MultipleExpectations
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("HENITAI_DEBUG_SCHEDULER").and_return("1")
      Henitai::Integration::SchedulerDiagnostics.reset!

      mutant_a = build_mutant("a")
      mutant_b = build_mutant("b")
      integration = instance_double(Henitai::Integration::Rspec)
      stub_fake_spawn_sequence(integration, [10, 11])
      stub_result_builder(integration)
      config = Struct.new(:timeout, :max_flaky_retries).new(10.0, 0)
      runner = build_fake_runner(
        worker_count: 1,
        wait2_results: [[10, build_wait_status(0)], nil, [11, build_wait_status(0)]]
      )

      results = runner.run([mutant_a, mutant_b], integration, config, nil)

      expect(results.size).to eq(2)
      expect(Henitai::Integration::SchedulerDiagnostics.summary[:max_concurrent]).to eq(1)
    end
  end

  describe "timeout isolation" do
    it "classifies timeout slots with fake process state and no real child process" do
      mutant = build_mutant("slow")
      runtime, runtime_state = build_fake_runtime(
        clock_times: [0.0, 0.2, 0.2],
        wait2_results: {
          -1 => [nil, nil],
          12 => [nil, nil, nil]
        },
        wait_results: {
          12 => build_wait_status(0)
        }
      )
      wakeup, = build_fake_wakeup
      integration = instance_double(Henitai::Integration::Rspec)
      stub_fake_spawn(integration, 12)
      stub_result_builder(integration)
      config = Struct.new(:timeout, :max_flaky_retries).new(0.1, 0)
      runner = described_class.new(
        worker_count: 1,
        runtime: runtime,
        wakeup: wakeup
      )

      results = runner.run([mutant], integration, config, nil)

      aggregate_failures do
        expect(results.map(&:status)).to eq([:timeout])
        expect(runtime_state[:kill_calls]).to eq([[:SIGTERM, -12], [:SIGKILL, -12]])
        expect(runtime_state[:wait_calls]).to eq([12])
      end
    end

    it "cleans up slots after timeout and leaves no active slots" do # rubocop:disable RSpec/MultipleExpectations
      mutant = build_mutant("slow")
      runtime, runtime_state = build_fake_runtime(
        clock_times: [0.0, 0.2, 0.2],
        wait2_results: {
          -1 => [nil, nil],
          13 => [nil, nil, nil]
        },
        wait_results: {
          13 => build_wait_status(0)
        }
      )
      wakeup, = build_fake_wakeup
      integration = instance_double(Henitai::Integration::Rspec)
      stub_fake_spawn(integration, 13)
      stub_result_builder(integration)
      config = Struct.new(:timeout, :max_flaky_retries).new(0.1, 0)
      runner = described_class.new(worker_count: 1, runtime: runtime, wakeup: wakeup)

      results = runner.run([mutant], integration, config, nil)

      expect(results.size).to eq(1)
      expect(results.first.status).to eq(:timeout)
      expect(runtime_state[:wait_calls]).to eq([13])
    end
  end

  describe "interrupt semantics" do
    it "raises Interrupt, reaps all children, and emits no result for in-flight mutants" do # rubocop:disable RSpec/MultipleExpectations
      mutant = build_mutant("slow")
      runtime, runtime_state = build_fake_runtime(
        clock_times: [0.0, 0.0],
        wait2_results: {
          -1 => [nil, nil],
          21 => [nil, nil]
        },
        wait_results: {
          21 => build_wait_status(0)
        }
      )
      runner = nil
      wakeup, = build_fake_wakeup(on_wait: ->(*) { runner.request_shutdown })
      integration = instance_double(Henitai::Integration::Rspec)
      stub_fake_spawn(integration, 21)
      stub_result_builder(integration)
      config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 0)
      runner = described_class.new(worker_count: 1, runtime: runtime, wakeup: wakeup)

      expect { runner.run([mutant], integration, config, nil) }.to raise_error(Interrupt)
      expect(mutant.status).to eq(:pending)
      expect(runtime_state[:kill_calls]).to eq([[:SIGTERM, -21], [:SIGKILL, -21]])
      expect(runtime_state[:wait_calls]).to eq([21])
    end

    it "does not refill a slot after shutdown is requested", :aggregate_failures do
      mutant_a = build_mutant("first")
      mutant_b = build_mutant("second")
      runtime, = build_fake_runtime(
        clock_times: [0.0, 0.0, 0.0],
        wait2_results: { -1 => [nil, [21, build_wait_status(1)]] },
        wait_results: { 22 => build_wait_status(0) }
      )
      runner = nil
      wakeup, = build_fake_wakeup(on_wait: ->(*) { runner.request_shutdown })
      integration = instance_double(Henitai::Integration::Rspec)
      stub_fake_spawn_sequence(integration, [21, 22])
      stub_result_builder(integration)
      config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 0)
      runner = described_class.new(worker_count: 1, runtime:, wakeup:)

      expect { runner.run([mutant_a, mutant_b], integration, config, nil) }
        .to raise_error(Interrupt)

      expect(integration).to have_received(:spawn_mutant).once
      expect(mutant_b.status).to eq(:pending)
    end
  end

  describe "spawn failure isolation" do
    it "does not crash other slots when one spawn raises" do # rubocop:disable RSpec/MultipleExpectations
      mutant_a = build_mutant("ok_a")
      mutant_b = build_mutant("fail")
      mutant_c = build_mutant("ok_c")

      integration = instance_double(Henitai::Integration::Rspec)
      stub_fake_spawn_sequence(integration, [10, RuntimeError.new("simulated fork failure"), 11])
      stub_result_builder(integration)

      config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 0)
      runner = build_fake_runner(
        worker_count: 3,
        wait2_results: [[10, build_wait_status(1)], [11, build_wait_status(1)]]
      )

      results = runner.run([mutant_a, mutant_b, mutant_c], integration, config, nil)

      expect(results.size).to eq(3)
      expect(mutant_b.status).to eq(:compile_error)
    end
  end

  describe "retry correctness" do
    it "retries within the same slot when retries remain and returns the final outcome" do # rubocop:disable RSpec/MultipleExpectations
      mutant = build_mutant("flaky")
      call_count = 0

      integration = instance_double(Henitai::Integration::Rspec)
      allow(integration).to receive(:select_tests).and_return([])
      allow(integration).to receive(:spawn_mutant) do |**|
        call_count += 1
        build_fake_handle(call_count == 1 ? 10 : 11)
      end
      stub_result_builder(integration)

      config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 1)
      runner = build_fake_runner(
        worker_count: 1,
        wait2_results: [[10, build_wait_status(0)], [11, build_wait_status(1)]]
      )

      results = runner.run([mutant], integration, config, nil)

      expect(results.size).to eq(1)
      expect(results.first.status).to eq(:killed)
      expect(call_count).to eq(2)
    end
  end

  describe "flaky retry counting" do
    it "counts each mutant that required at least one retry" do
      flaky = build_mutant("flaky")
      stable = build_mutant("stable")
      call_counts = Hash.new(0)

      integration = instance_double(Henitai::Integration::Rspec)
      allow(integration).to receive(:select_tests).and_return([])
      allow(integration).to receive(:spawn_mutant) do |mutant:, **|
        call_counts[mutant.id] += 1
        pid = mutant.id == "flaky" ? 9 + call_counts[mutant.id] : 12
        build_fake_handle(pid)
      end
      stub_result_builder(integration)

      config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 1)
      runner = build_fake_runner(
        worker_count: 1,
        wait2_results: [
          [10, build_wait_status(0)], [11, build_wait_status(1)], nil,
          [12, build_wait_status(1)]
        ]
      )

      runner.run([flaky, stable], integration, config, nil)

      expect(runner.flaky_retry_count).to eq(1)
    end

    it "reports zero retries when no mutant survives its first run" do
      stable = build_mutant("stable")
      integration = instance_double(Henitai::Integration::Rspec)
      stub_fake_spawn_sequence(integration, [10])
      stub_result_builder(integration)
      config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 3)
      runner = build_fake_runner(
        worker_count: 1,
        wait2_results: [[10, build_wait_status(1)]]
      )

      runner.run([stable], integration, config, nil)

      expect(runner.flaky_retry_count).to eq(0)
    end

    it "does not count a retry whose respawn fails to spawn" do # rubocop:disable RSpec/MultipleExpectations
      mutant = build_mutant("flaky")
      call_count = 0

      integration = instance_double(Henitai::Integration::Rspec)
      allow(integration).to receive(:select_tests).and_return([])
      allow(integration).to receive(:spawn_mutant) do |**|
        call_count += 1
        raise "simulated fork failure" if call_count == 2 # fails on the retry attempt

        build_fake_handle(10)
      end
      stub_result_builder(integration)

      config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 1)
      runner = build_fake_runner(
        worker_count: 1,
        wait2_results: [[10, build_wait_status(0)]]
      )

      results = runner.run([mutant], integration, config, nil)

      expect(runner.flaky_retry_count).to eq(0)
      expect(results.first.status).to eq(:compile_error)
    end
  end
end
