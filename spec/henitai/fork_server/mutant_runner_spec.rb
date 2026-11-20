# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe Henitai::ForkServer::MutantRunner, :aggregate_failures do
  let(:client) { instance_double(Henitai::ForkServer::Client, shutdown: nil, abandon: nil, lost?: false) }
  let(:integration) do
    instance_double(
      Henitai::Integration::Rspec,
      mutant_log_paths: { report_path: "r.json" },
      build_result: :result
    )
  end
  let(:report_store) { instance_double(Henitai::Integration::ChildReportStore, clear: nil) }
  let(:warnings) { [] }
  let(:runner) do
    described_class.new(integration:, client:, report_store:, warner: ->(message) { warnings << message })
  end
  let(:mutant) { instance_double(Henitai::Mutant, id: "m1") }

  it "abandons the server when it is lost, so it cannot fork a mutant that runs locally" do
    allow(client).to receive(:spawn_mutant).and_raise(Henitai::ForkServer::Client::ServerLost, "gone")
    allow(integration).to receive(:spawn_mutant).and_return(Henitai::Integration::ChildHandle.new(5, {}))

    runner.spawn_mutant(mutant:, test_files: ["a_spec.rb"])

    expect(client).to have_received(:abandon).once
    expect(warnings.first).to include("gone")
  end

  it "deactivates as soon as the client reports the server lost, even with nothing pending" do
    allow(client).to receive(:lost?).and_return(true)

    2.times { expect(runner.active?).to be(false) }

    expect(warnings.size).to eq(1)
    expect(client).to have_received(:abandon).once
  end

  describe "the fallback timeout" do
    let(:fallback_timeout) { ->(test_files) { test_files.size + 100.0 } }
    let(:runner) do
      described_class.new(integration:, client:, report_store:, fallback_timeout:, warner: ->(_) {})
    end

    it "gives a locally spawned child the same boot-inclusive timeout" do
      allow(client).to receive(:spawn_mutant).and_raise(Henitai::ForkServer::Client::SpawnFailed)
      allow(integration).to receive(:spawn_mutant).and_return(Henitai::Integration::ChildHandle.new(5, {}))
      allow(runner.runtime).to receive(:local)

      handle = runner.spawn_mutant(mutant:, test_files: ["a_spec.rb"])

      expect([handle.pid, handle.timeout]).to eq([5, 101.0])
    end
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

      expect(handle.to_a).to eq([77, { report_path: "r.json" }, nil])
      expect(runtime).to have_received(:served).with(77)
      expect(client).to have_received(:spawn_mutant)
        .with(hash_including(env: { "HENITAI_WORKER_SLOT" => "2" }))
      expect(report_store).to have_received(:clear).with("r.json")
    end

    it "forks locally without asking the server once the runner is stopped" do
      allow(client).to receive(:spawn_mutant).and_return(77)
      runner.stop

      expect(spawn.pid).to eq(5)
      expect(client).not_to have_received(:spawn_mutant)
    end

    it "exports no worker slot to the server when the scheduler set none" do
      allow(client).to receive(:spawn_mutant).and_return(77)
      ENV.delete("HENITAI_WORKER_SLOT")

      spawn

      expect(client).to have_received(:spawn_mutant).with(hash_including(env: {}))
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

    it "forks a local child the server never sees, registered with the runtime" do
      allow(client).to receive(:spawn_mutant).and_return(77)

      handle = runner.spawn_local(mutant:, test_files: ["a_spec.rb"])

      expect(handle.pid).to eq(5)
      expect(client).not_to have_received(:spawn_mutant)
      expect(runtime).to have_received(:local).with(5)
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
