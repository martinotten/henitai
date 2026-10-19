# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe Henitai::ForkServer::MutantRunner, :aggregate_failures do
  let(:client) { instance_double(Henitai::ForkServer::Client, shutdown: nil) }
  let(:integration) do
    instance_double(
      Henitai::Integration::Rspec,
      mutant_log_paths: { report_path: "r.json" },
      build_result: :result,
      cleanup_process_group: nil,
      run_mutant: :fallback_result
    )
  end
  let(:report_store) { instance_double(Henitai::Integration::ChildReportStore, clear: nil) }
  let(:warnings) { [] }
  let(:runner) do
    described_class.new(integration:, client:, report_store:, warner: ->(message) { warnings << message })
  end
  let(:mutant) { instance_double(Henitai::Mutant, id: "m1") }
  let(:status) { Henitai::ForkServer::Status.new(exitstatus: 1, termsig: nil) }

  def run
    runner.run_mutant(mutant:, test_files: ["a_spec.rb"], timeout: 2.0)
  end

  it "runs a mutant through the server and builds the result from the relayed status" do
    allow(client).to receive_messages(spawn_mutant: 77, wait_exit: status)

    expect(run).to eq(:result)
    expect(client).to have_received(:spawn_mutant)
      .with(mutant_id: "m1", test_files: ["a_spec.rb"], log_paths: { report_path: "r.json" }, env: {})
    expect(integration).to have_received(:build_result).with(status, { report_path: "r.json" })
    expect(report_store).to have_received(:clear).with("r.json")
  end

  it "kills the process group and reports a timeout when no exit arrives" do
    allow(client).to receive_messages(spawn_mutant: 77, wait_exit: nil, forget: nil)

    run

    expect(integration).to have_received(:cleanup_process_group).with(77).once
    expect(client).to have_received(:forget).with(77)
    expect(integration).to have_received(:build_result).with(:timeout, anything)
  end

  it "runs a mutant the server cannot fork on the per-mutant path" do
    allow(client).to receive(:spawn_mutant).and_raise(Henitai::ForkServer::Client::SpawnFailed)

    expect(run).to eq(:fallback_result)
    expect(runner).to be_active
  end

  it "deactivates with one warning when the server is lost and keeps falling back" do
    allow(client).to receive(:spawn_mutant).and_raise(Henitai::ForkServer::Client::ServerLost, "gone")

    2.times { expect(run).to eq(:fallback_result) }

    expect([runner.active?, warnings.size]).to eq([false, 1])
  end

  describe "#spawn_mutant" do
    let(:runtime) { instance_double(Henitai::ForkServer::Runtime, served: nil, local: nil) }

    after { ENV.delete("HENITAI_WORKER_SLOT") }

    before do
      allow(Henitai::ForkServer::Runtime).to receive(:new).and_return(runtime)
      allow(integration).to receive(:spawn_mutant).and_return(Henitai::Integration::ChildHandle.new(5, {}))
    end

    def spawn
      runner.spawn_mutant(mutant:, test_files: ["a_spec.rb"])
    end

    it "forks through the server, passing the scheduler's worker slot" do
      allow(client).to receive(:spawn_mutant).and_return(77)

      ENV["HENITAI_WORKER_SLOT"] = "2"
      handle = spawn

      expect(handle.to_a).to eq([77, { report_path: "r.json" }])
      expect(runtime).to have_received(:served).with(77)
      expect(client).to have_received(:spawn_mutant)
        .with(hash_including(env: { "HENITAI_WORKER_SLOT" => "2" }))
      expect(report_store).to have_received(:clear).with("r.json")
    end

    it "forks locally when the server cannot fork the mutant" do
      allow(client).to receive(:spawn_mutant).and_raise(Henitai::ForkServer::Client::SpawnFailed)

      expect(spawn.pid).to eq(5)
      expect(runtime).to have_received(:local).with(5)
    end

    it "deactivates with one warning when the server is lost and forks locally from then on" do
      allow(client).to receive(:spawn_mutant).and_raise(Henitai::ForkServer::Client::ServerLost, "gone")

      2.times { expect(spawn.pid).to eq(5) }

      expect([runner.active?, warnings.size]).to eq([false, 1])
    end

    it "answers the scheduler's other integration calls from the real integration" do
      allow(integration).to receive_messages(select_tests: ["t"], test_files: ["f"])

      expect([runner.select_tests(:subject), runner.test_files, runner.build_result(:x, {})])
        .to eq([["t"], ["f"], :result])
    end
  end

  it "exposes one runtime for the scheduler" do
    first = runner.runtime

    expect(runner.runtime).to be(first)
  end

  it "stops the server" do
    runner.stop

    expect([runner.active?, client]).to eq([false, client])
    expect(client).to have_received(:shutdown)
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
