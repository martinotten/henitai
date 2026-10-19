# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ForkServer::Runtime, :aggregate_failures do
  let(:client) { instance_double(Henitai::ForkServer::Client, io: :socket, lost?: false) }
  let(:base) { instance_double(Henitai::ProcessWorkerRunner::Runtime) }
  let(:runtime) { described_class.new(client:, base:) }
  let(:status) { Henitai::ForkServer::Status.new(exitstatus: 0, termsig: nil) }

  it "completes a served pid from the relayed exit, once" do
    runtime.served(7)
    allow(client).to receive_messages(poll_exit: status, poll_any_exit: nil)

    expect(runtime.wait2(7, Process::WNOHANG)).to eq([7, status])
    expect(runtime.wait2(-1, Process::WNOHANG)).to be_nil
  end

  it "reports nothing for a served pid that is still running" do
    runtime.served(7)
    allow(client).to receive(:poll_exit).and_return(nil)

    expect(runtime.wait2(7, Process::WNOHANG)).to be_nil
  end

  it "reaps any served exit for a wait on any child" do
    runtime.served(7)
    allow(client).to receive(:poll_any_exit).and_return([7, status])

    expect(runtime.wait2(-1, Process::WNOHANG)).to eq([7, status])
  end

  it "waits on locally forked pids itself and never on the server's" do
    runtime.local(8)
    allow(client).to receive(:poll_any_exit).and_return(nil)
    allow(base).to receive(:wait2).with(8, Process::WNOHANG).and_return([8, :real], nil)

    expect([runtime.wait2(-1, Process::WNOHANG), runtime.wait2(-1, Process::WNOHANG)]).to eq([[8, :real], nil])
    expect(base).to have_received(:wait2).once
  end

  it "waits on a pid it does not know through the base runtime" do
    allow(base).to receive(:wait2).with(9, 0).and_return([9, :real])

    expect(runtime.wait2(9, 0)).to eq([9, :real])
  end

  it "blocks for a served pid's exit and for a local pid through the base" do
    runtime.served(7)
    runtime.local(8)
    allow(client).to receive(:wait_exit).with(7, described_class::WAIT_SECONDS).and_return(status)
    allow(base).to receive(:wait).with(8).and_return(8)

    expect([runtime.wait(7), runtime.wait(8)]).to eq([status, 8])
  end

  it "settles a blocking wait with the synthesized exit when the server is lost" do
    runtime.served(7)
    allow(client).to receive(:wait_exit).and_raise(Henitai::ForkServer::Client::ServerLost)
    allow(client).to receive(:poll_exit).with(7).and_return(status)

    expect(runtime.wait(7)).to eq(status)
  end

  it "wakes the event loop on the server connection until it is lost" do
    expect(runtime.wakeup_ios).to eq([:socket])

    allow(client).to receive(:lost?).and_return(true)

    expect(runtime.wakeup_ios).to eq([])
  end

  it "delegates clock, signals, pausing and traps to the base runtime" do
    allow(base).to receive_messages(clock_gettime: 1.5, kill: 1, pause: nil, trap: "DEFAULT")

    expect(runtime.clock_gettime(Process::CLOCK_MONOTONIC)).to eq(1.5)
    expect(runtime.kill(:SIGKILL, -5)).to eq(1)
    expect(runtime.pause(0.1)).to be_nil
    expect(runtime.trap("INT", "IGNORE")).to eq("DEFAULT")
    expect(base).to have_received(:kill).with(:SIGKILL, -5)
  end
end
