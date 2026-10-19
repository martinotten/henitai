# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ForkServer, :aggregate_failures do
  let(:client) { instance_double(described_class::Client, shutdown: nil) }
  let(:warnings) { [] }
  let(:integration) { instance_double(Henitai::Integration::Rspec) }

  def start
    described_class.start(integration:, mutants: [], test_files: ["a_spec.rb"], log_path: "fs.log",
                          warner: ->(message) { warnings << message })
  end

  before do
    allow(described_class::ServerProcess).to receive(:start).and_return(client)
  end

  it "returns a runner once the server is ready" do
    allow(client).to receive(:wait_until_ready)

    expect(start).to be_a(described_class::MutantRunner)
  end

  it "warns, shuts the server down and returns nil when it fails to boot" do
    allow(client).to receive(:wait_until_ready).and_raise(described_class::Client::BootFailed, "boom")

    expect(start).to be_nil
    expect(client).to have_received(:shutdown)
    expect(warnings.first).to match(/failed to boot \(boom\).*fs\.log.*falling back/)
  end

  it "falls back when the server dies while booting" do
    allow(client).to receive(:wait_until_ready).and_raise(described_class::Client::ServerLost, "closed")

    expect(start).to be_nil
  end
end
