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
end
