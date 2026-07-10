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

  def build_mutant(id)
    subject = Struct.new(:expression).new("Foo##{id}")
    Struct.new(:id, :subject, :status) do
      def pending? = status == :pending
    end.new(id, subject, :pending)
  end

  def fake_log_paths
    { stdout_path: "/dev/null", stderr_path: "/dev/null", log_path: "/dev/null" }
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

  def build_barrier_integration(barrier_dir:, expected:)
    integration = instance_double(Henitai::Integration::Rspec)
    allow(integration).to receive(:select_tests).and_return([])
    allow(integration).to receive(:spawn_mutant) do |mutant:, **|
      pid = Process.fork { run_barrier_child(barrier_dir, expected, mutant.id) }
      Henitai::Integration::ChildHandle.new(pid, fake_log_paths)
    end
    stub_result_builder(integration)
    integration
  end

  def build_pipe_blocking_integration(release_reader, release_writer)
    integration = instance_double(Henitai::Integration::Rspec)
    allow(integration).to receive(:select_tests).and_return([])
    allow(integration).to receive(:spawn_mutant) do |**|
      pid = Process.fork do
        release_writer.close
        release_reader.read
        Process.exit(0)
      end
      Henitai::Integration::ChildHandle.new(pid, fake_log_paths)
    end
    stub_result_builder(integration)
    integration
  end

  def run_barrier_child(barrier_dir, expected, marker_id)
    File.write(File.join(barrier_dir, marker_id.to_s), "")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5.0
    until Dir.children(barrier_dir).size >= expected
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      Thread.pass
    end
    Process.exit(0)
  end

  it "runs four mutants concurrently with real OS-level overlap" do # rubocop:disable RSpec/MultipleExpectations
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("HENITAI_DEBUG_SCHEDULER").and_return("1")
    Henitai::Integration::SchedulerDiagnostics.reset!

    Dir.mktmpdir do |barrier_dir|
      mutants = (1..4).map { |index| build_mutant("m#{index}") }
      integration = build_barrier_integration(barrier_dir: barrier_dir, expected: 4)
      config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 0)

      results = described_class.new(worker_count: 4).run(mutants, integration, config, nil)

      expect(results.size).to eq(4)
      expect(Henitai::Integration::SchedulerDiagnostics.summary[:max_concurrent]).to eq(4)
    end
  end

  it "waits on a wakeup io while children are active" do
    release_reader, release_writer = IO.pipe
    mutant = build_mutant("wakeup")
    integration = build_pipe_blocking_integration(release_reader, release_writer)
    config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 0)

    allow(IO).to receive(:select).and_wrap_original do |original, *args|
      release_writer.close unless release_writer.closed?
      original.call(*args)
    end

    described_class.new(worker_count: 1).run([mutant], integration, config, nil)

    expect(IO).to have_received(:select).with(
      array_including(instance_of(IO)), nil, nil, kind_of(Numeric)
    )
  ensure
    [release_reader, release_writer].compact.each { |io| io.close unless io.closed? }
  end
end
