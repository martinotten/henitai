# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Integration::Rspec do
  def stub_timeout_child(integration, record, child_pid:, raise_esrch_on_kill: false)
    stub_process_exit(record)
    stub_process_fork(record, child_pid)
    stub_process_wait(record)
    stub_process_clock
    stub_process_kill(record, raise_esrch_on_kill)
    stub_mutant_runtime(integration)
  end

  def stub_process_exit(record)
    allow(Process).to receive(:exit) { |status| record[:child_status] = status }
  end

  def stub_process_fork(record, child_pid)
    allow(Process).to receive(:fork) do |&block|
      record[:forked] = true
      block.call
      child_pid
    end
  end

  def stub_process_wait(record)
    allow(Process).to receive(:wait) do |pid, flags = nil|
      if flags == Process::WNOHANG
        nil
      else
        record[:reaped] = pid
        pid
      end
    end
  end

  def stub_process_clock
    allow(Process).to receive(:clock_gettime).and_return(0.0, 0.2)
  end

  def stub_process_kill(record, raise_esrch_on_kill)
    allow(Process).to receive(:kill) do |signal, pid|
      record[:signals] << [signal, pid]
      raise Errno::ESRCH if raise_esrch_on_kill && signal == :SIGKILL
    end
  end

  def stub_mutant_runtime(integration)
    allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
    allow(integration).to receive_messages(run_tests: 0, pause: nil)
  end

  it "forks a child, sets the mutant id, and waits with timeout" do
    mutant = Struct.new(:id).new("mutant-1")
    integration = described_class.new
    record = {}
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      allow(Process).to receive(:exit) { |status| record[:child_status] = status }
      allow(Process).to receive(:fork) do |&block|
        record[:forked] = true
        block.call
        record[:env_id] = ENV.fetch("HENITAI_MUTANT_ID", nil)
        4321
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(integration).to receive(:run_tests).and_return(0)
      allow(Process).to receive(:wait) do |pid, flags|
        record[:wait_args] = [pid, flags]
        4321
      end
      allow(Process).to receive(:last_status).and_return(
        Struct.new(:success?).new(true)
      )

      record[:result] = integration.run_mutant(
        mutant:,
        test_files: ["spec/foo_spec.rb"],
        timeout: 1.5
      )

      expect(record).to eq(
        forked: true,
        child_status: 0,
        env_id: "mutant-1",
        wait_args: [4321, Process::WNOHANG],
        result: :survived
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "activates the mutant before running child tests" do
    mutant = Struct.new(:id).new("mutant-2")
    integration = described_class.new
    order = []
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      allow(Process).to receive(:exit) { |status| order << [:exit, status] }
      allow(Process).to receive(:fork) do |&block|
        order << :fork
        block.call
        9876
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!) do |_mutant|
        order << :activate
        0
      end
      allow(RSpec::Core::Runner).to receive(:run) do |test_files|
        order << [:rspec, test_files]
        0
      end
      allow(integration).to receive(:wait_with_timeout) do |pid, timeout|
        order << [:wait, pid, timeout]
        :survived
      end

      integration.run_mutant(
        mutant:,
        test_files: ["spec/bar_spec.rb"],
        timeout: 2.0
      )

      expect(order).to eq(
        [
          :fork,
          :activate,
          [:rspec, ["spec/bar_spec.rb"]],
          [:exit, 0],
          [:wait, 9876, 2.0]
        ]
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "returns the rspec exit status from run_tests" do
    integration = described_class.new

    allow(RSpec::Core::Runner).to receive(:run).and_return(1)

    expect(integration.send(:run_tests, ["spec/failing_spec.rb"])).to eq(1)
  end

  it "escalates a stuck child from SIGTERM to SIGKILL" do
    mutant = Struct.new(:id).new("mutant-3")
    integration = described_class.new
    record = { pauses: [], signals: [] }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_timeout_child(integration, record, child_pid: 2468)
      allow(integration).to receive(:pause) do |seconds|
        record[:pauses] << seconds
      end

      record[:result] = integration.run_mutant(
        mutant:,
        test_files: ["spec/baz_spec.rb"],
        timeout: 0.1
      )

      expect(record).to include(
        signals: [[:SIGTERM, 2468], [:SIGKILL, 2468]],
        forked: true,
        child_status: 0,
        result: :timeout
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "reaps a timed-out child even if it exits after SIGTERM" do
    mutant = Struct.new(:id).new("mutant-3b")
    integration = described_class.new
    record = { signals: [] }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_timeout_child(
        integration,
        record,
        child_pid: 2469,
        raise_esrch_on_kill: true
      )

      record[:result] = integration.run_mutant(
        mutant:,
        test_files: ["spec/baz_spec.rb"],
        timeout: 0.1
      )

      expect(record).to include(
        signals: [[:SIGTERM, 2469], [:SIGKILL, 2469]],
        reaped: 2469,
        forked: true,
        child_status: 0,
        result: :timeout
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "exits the child with status 1 when RSpec reports a failure" do
    mutant = Struct.new(:id).new("mutant-4")
    integration = described_class.new
    record = {}
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      allow(Process).to receive(:exit) { |status| record[:child_status] = status }
      allow(Process).to receive(:fork) do |&block|
        block.call
        1357
      end
      allow(Process).to receive_messages(
        wait: 1357,
        last_status: Struct.new(:success?).new(false)
      )
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(integration).to receive(:pause).and_return(nil)
      allow(RSpec::Core::Runner).to receive(:run) do |test_files|
        record[:rspec_files] = test_files
        1
      end

      record[:result] = integration.run_mutant(
        mutant:,
        test_files: ["spec/failing_spec.rb"],
        timeout: 0.1
      )

      expect(record).to include(
        rspec_files: ["spec/failing_spec.rb"],
        child_status: 1,
        result: :killed
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end
end
