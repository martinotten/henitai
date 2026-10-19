# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "Process group cleanup after a normal child exit" do # rubocop:disable RSpec/DescribeClass -- covers both the linear and the parallel cleanup paths
  after do
    loop do
      pid = Process.wait(-1, Process::WNOHANG)
      break unless pid
    end
  rescue Errno::ECHILD
    nil
  end

  def spawn_leader_with_grandchild(marker)
    Process.fork do
      Process.setpgid(0, 0)
      grandchild = spawn("sleep", "30")
      File.write(marker, grandchild.to_s)
      Process.exit!(0)
    end
  end

  def read_grandchild(marker)
    Integer(File.read(marker))
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def dead_within?(pid, timeout)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    while alive?(pid)
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.02
    end
    true
  end

  def elapsed_seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  def force_kill(pid)
    Process.kill(:KILL, pid)
  rescue Errno::ESRCH
    nil
  end

  def fake_log_paths
    { stdout_path: "/dev/null", stderr_path: "/dev/null", log_path: "/dev/null" }
  end

  def build_mutant
    subject = Struct.new(:expression).new("Foo#bar")
    Struct.new(:id, :subject, :status) do
      def pending? = status == :pending
    end.new("cleanup", subject, :pending)
  end

  def build_leader_integration(marker)
    integration = instance_double(Henitai::Integration::Rspec)
    allow(integration).to receive(:select_tests).and_return([])
    allow(integration).to receive(:spawn_mutant) do |**|
      pid = spawn_leader_with_grandchild(marker)
      Henitai::Integration::ChildHandle.new(pid, fake_log_paths)
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

  it "terminates a grandchild quickly after a linear-path normal exit" do
    Dir.mktmpdir do |dir|
      marker = File.join(dir, "grandchild.pid")
      leader = spawn_leader_with_grandchild(marker)
      Process.wait(leader)
      grandchild = read_grandchild(marker)

      outcome = {
        alive_before: alive?(grandchild),
        fast: elapsed_seconds { Henitai::Integration::Base.new.cleanup_process_group(leader) } < 1.0,
        dead_after: dead_within?(grandchild, 1.0)
      }

      expect(outcome).to eq(alive_before: true, fast: true, dead_after: true)
    ensure
      force_kill(grandchild) if grandchild
    end
  end

  it "terminates a grandchild left behind by a parallel child that exits normally" do
    Dir.mktmpdir do |dir|
      marker = File.join(dir, "grandchild.pid")
      integration = build_leader_integration(marker)
      config = Struct.new(:timeout, :max_flaky_retries).new(5.0, 0)

      Henitai::ProcessWorkerRunner.new(worker_count: 1).run([build_mutant], integration, config, nil)
      grandchild = read_grandchild(marker)

      expect(dead_within?(grandchild, 1.0)).to be(true)
    ensure
      force_kill(grandchild) if grandchild
    end
  end
end
