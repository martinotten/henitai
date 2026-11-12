# frozen_string_literal: true

require "spec_helper"

# Control jobs (ADR-19 §2) run through the scheduler's public loop API:
# enqueue_control, fill_idle_slots, reap_all_completed_children,
# check_timeouts and drain_draining_slots.
RSpec.describe Henitai::SlotScheduler::ControlSlots do
  let(:slot_table) { Henitai::SlotScheduler::SlotTable.new }
  let(:listener) { Struct.new(:finished) { def control_finished(key, result) = finished << [key, result] }.new([]) }
  let(:control_mutant) { Struct.new(:id, :subject).new("control", Struct.new(:expression).new("Foo#bar")) }
  let(:handle) do
    Henitai::Integration::ChildHandle.new(4242, { stdout_path: "/dev/null", stderr_path: "/dev/null",
                                                  log_path: "/dev/null" })
  end

  def build_mutant(id)
    Struct.new(:id, :subject, :status, :covered_by, :tests_completed) do
      def pending? = status == :pending
    end.new(id, Struct.new(:expression).new("Foo##{id}"), :pending)
  end

  def build_runtime(*wait2_results)
    runtime = instance_double(Henitai::ProcessWorkerRunner::Runtime, pause: nil, wait: nil)
    allow(runtime).to receive_messages(clock_gettime: 0.0, kill: 1)
    allow(runtime).to receive(:wait2).and_return(*wait2_results, nil)
    allow(runtime).to receive(:kill).with(0, anything).and_raise(Errno::ESRCH)
    runtime
  end

  def build_host(runtime: build_runtime, shutdown: false)
    Struct.new(:worker_count, :runtime, :wakeup) { define_method(:shutdown_requested?) { shutdown } }
          .new(1, runtime, nil)
  end

  def build_integration
    integration = instance_double(Henitai::Integration::Rspec, select_tests: ["spec/foo_spec.rb"])
    allow(integration).to receive(:spawn_mutant).and_return(handle)
    integration
  end

  def build_scheduler(integration:, host: build_host, progress_reporter: nil)
    Henitai::SlotScheduler.new(
      integration:, config: Struct.new(:timeout, :max_flaky_retries).new(10.0, 3),
      progress_reporter:, options: {}, host:, slot_table:,
      flaky_tests: Henitai::FlakyTestRegistry.new(["spec/control_spec.rb"]), control_listener: listener
    )
  end

  def result(status)
    Henitai::ScenarioExecutionResult.new(status:, stdout: "out", stderr: "", log_path: "/dev/null",
                                         killing_tests: ["spec/control_spec.rb"])
  end

  it "runs a queued control before pending mutants, with the group's test files" do
    integration = build_integration
    scheduler = build_scheduler(integration:)
    scheduler.enqueue([build_mutant("a")])
    scheduler.enqueue_control(:group, control_mutant, ["spec/control_spec.rb"])

    scheduler.fill_idle_slots

    expect(integration).to have_received(:spawn_mutant)
      .with(mutant: control_mutant, test_files: ["spec/control_spec.rb"])
  end

  it "spawns a control locally when the integration offers a local path" do
    integration = instance_double(Henitai::ForkServer::MutantRunner, spawn_local: handle, spawn_mutant: handle)
    scheduler = build_scheduler(integration:)
    scheduler.enqueue_control(:group, control_mutant, ["spec/control_spec.rb"])

    scheduler.fill_idle_slots

    expect(integration).to have_received(:spawn_local)
      .with(mutant: control_mutant, test_files: ["spec/control_spec.rb"])
  end

  it "is not done while a control is queued" do
    scheduler = build_scheduler(integration: build_integration)
    scheduler.enqueue_control(:group, control_mutant, [])

    expect(scheduler.done?).to be(false)
  end

  it "reports a finished control to the listener once, without retry, result or progress", :aggregate_failures do
    integration = build_integration
    allow(integration).to receive(:build_result).and_return(result(:killed))
    progress = instance_double(Henitai::Reporter::Terminal, progress: nil)
    scheduler = build_scheduler(integration:, progress_reporter: progress,
                                host: build_host(runtime: build_runtime([4242, :status])))
    scheduler.enqueue_control(:group, control_mutant, ["spec/control_spec.rb"])
    scheduler.fill_idle_slots

    scheduler.reap_all_completed_children

    expect(listener.finished.map { |key, finished| [key, finished.status] }).to eq([%i[group killed]])
    expect([scheduler.results, scheduler.done?, scheduler.flaky_retry_count]).to eq([[], true, 0])
    expect(progress).not_to have_received(:progress)
    expect(integration).to have_received(:spawn_mutant).once
  end

  it "reports a timed-out control to the listener" do
    integration = build_integration
    allow(integration).to receive(:build_result).with(:timeout, anything).and_return(result(:timeout))
    runtime = build_runtime
    scheduler = build_scheduler(integration:, host: build_host(runtime:))
    scheduler.enqueue_control(:group, control_mutant, [])
    scheduler.fill_idle_slots
    allow(runtime).to receive(:clock_gettime).and_return(100.0)

    scheduler.check_timeouts
    scheduler.drain_draining_slots

    expect(listener.finished.map { |key, finished| [key, finished.status] }).to eq([%i[group timeout]])
  end

  it "reports a control that cannot be spawned as a failed control" do
    integration = build_integration
    allow(integration).to receive(:spawn_mutant).and_raise(StandardError, "no fork")
    scheduler = build_scheduler(integration:)
    scheduler.enqueue_control(:group, control_mutant, [])

    scheduler.fill_idle_slots

    expect(listener.finished.map { |key, finished| [key, finished.status] }).to eq([%i[group compile_error]])
  end

  it "reports nothing for a control interrupted by shutdown" do
    integration = build_integration
    scheduler = build_scheduler(integration:)
    scheduler.enqueue_control(:group, control_mutant, [])
    scheduler.fill_idle_slots

    scheduler.interrupt_active_slots
    scheduler.drain_draining_slots

    expect([listener.finished, scheduler.done?]).to eq([[], true])
  end
end
