# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SlotScheduler do
  def build_scheduler
    described_class.new(
      integration: nil,
      config: nil,
      progress_reporter: nil,
      options: {},
      host: nil
    )
  end

  describe "HENITAI_WORKER_SLOT" do
    around do |example|
      original = ENV.fetch("HENITAI_WORKER_SLOT", nil)
      example.run
    ensure
      original.nil? ? ENV.delete("HENITAI_WORKER_SLOT") : ENV["HENITAI_WORKER_SLOT"] = original
    end

    def build_worker_mutant(id)
      subject = Struct.new(:expression).new("Foo##{id}")
      Struct.new(:id, :subject, :status, :covered_by, :tests_completed) do
        def pending? = status == :pending
      end.new(id, subject, :pending)
    end

    def build_host(worker_count)
      Struct.new(:worker_count, :runtime, :wakeup) do
        def shutdown_requested? = false
      end.new(worker_count, Henitai::ProcessWorkerRunner::Runtime.new, nil)
    end

    def build_capturing_integration(captured)
      integration = instance_double(Henitai::Integration::Rspec)
      pids = (1000..).each
      allow(integration).to receive(:spawn_mutant) do |**|
        captured << ENV.fetch("HENITAI_WORKER_SLOT", nil)
        Henitai::Integration::ChildHandle.new(
          pids.next,
          { stdout_path: "/dev/null", stderr_path: "/dev/null", log_path: "/dev/null" }
        )
      end
      integration
    end

    def build_worker_scheduler(captured, worker_count:, max_flaky_retries: 0)
      described_class.new(
        integration: build_capturing_integration(captured),
        config: Struct.new(:timeout, :max_flaky_retries).new(10.0, max_flaky_retries),
        progress_reporter: nil,
        options: { test_files: [] },
        host: build_host(worker_count)
      )
    end

    it "injects distinct slot values from 0..jobs-1 at initial spawn" do
      captured = []
      scheduler = build_worker_scheduler(captured, worker_count: 2)
      scheduler.enqueue([build_worker_mutant("a"), build_worker_mutant("b"), build_worker_mutant("c")])

      scheduler.fill_idle_slots

      expect(captured).to eq(%w[0 1])
    end
  end
end
