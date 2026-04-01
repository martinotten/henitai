# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Integration::Rspec do
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
      allow(integration).to receive(:run_tests).and_return(0)
      allow(integration).to receive(:wait_with_timeout) do |pid, timeout|
        record[:wait_args] = [pid, timeout]
        :survived
      end

      record[:result] = integration.run_mutant(
        mutant:,
        test_files: ["spec/foo_spec.rb"],
        timeout: 1.5
      )

      expect(record).to eq(
        forked: true,
        child_status: 0,
        env_id: "mutant-1",
        wait_args: [4321, 1.5],
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
      allow(integration).to receive(:activate_mutant) do |_mutant|
        order << :activate
        0
      end
      allow(integration).to receive(:run_tests) do |test_files|
        order << [:tests, test_files]
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
          [:tests, ["spec/bar_spec.rb"]],
          [:exit, 0],
          [:wait, 9876, 2.0]
        ]
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "escalates a stuck child from SIGTERM to SIGKILL" do
    mutant = Struct.new(:id).new("mutant-3")
    integration = described_class.new
    record = { pauses: [], signals: [] }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      allow(Process).to receive(:exit) { |status| record[:child_status] = status }
      allow(Process).to receive(:fork) do |&block|
        record[:forked] = true
        block.call
        2468
      end
      allow(Process).to receive(:wait).and_return(nil, nil)
      allow(Process).to receive(:clock_gettime).and_return(0.0, 0.2)
      allow(Process).to receive(:kill) do |signal, pid|
        record[:signals] << [signal, pid]
      end
      allow(integration).to receive_messages(
        activate_mutant: 0,
        run_tests: 0
      )
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
        wait: Process::Status.allocate,
        clock_gettime: 0.0
      )
      allow(integration).to receive_messages(
        activate_mutant: 0,
        pause: nil
      )
      allow(RSpec::Core::Runner).to receive(:run) do |test_files|
        record[:rspec_files] = test_files
        false
      end

      integration.run_mutant(
        mutant:,
        test_files: ["spec/failing_spec.rb"],
        timeout: 0.1
      )

      expect(record).to include(
        rspec_files: ["spec/failing_spec.rb"],
        child_status: 1
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end
end
