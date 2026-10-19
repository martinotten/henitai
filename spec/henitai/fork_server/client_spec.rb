# frozen_string_literal: true

require "socket"
require "spec_helper"

RSpec.describe Henitai::ForkServer::Client, :aggregate_failures do
  let(:protocol) { Henitai::ForkServer::Protocol }
  let(:sockets) { UNIXSocket.pair }
  let(:server) { sockets.last }
  let(:server_reader) { protocol::Reader.new(server) }
  let(:client) { described_class.new(socket: sockets.first, pid: nil) }

  after { sockets.each { |socket| socket.close unless socket.closed? } }

  def tell(message)
    server.write(protocol.encode(message))
  end

  # Spawns mutants the server reports as +pids+, making them outstanding.
  # Request ids follow the client's sequence, starting at 1 for a fresh client.
  def spawn_outstanding(*pids)
    pids.each_with_index do |pid, index|
      tell("type" => "spawned", "request_id" => index + 1, "pid" => pid)
    end
    pids.each { client.spawn_mutant(mutant_id: "m", test_files: [], log_paths: {}) }
  end

  it "waits until the server is ready" do
    tell("type" => "ready")

    expect(client.wait_until_ready(1)).to be_nil
  end

  it "raises BootFailed with the server's reason" do
    tell("type" => "boot_failed", "reason" => "boom")

    expect { client.wait_until_ready(1) }.to raise_error(described_class::BootFailed, "boom")
  end

  it "raises BootFailed when the server stays silent" do
    expect { client.wait_until_ready(0.05) }.to raise_error(described_class::BootFailed, /did not become ready/)
  end

  it "raises ServerLost when the server closes the connection" do
    server.close

    expect { client.wait_until_ready(1) }.to raise_error(described_class::ServerLost)
  end

  it "sends a run request and returns the pid from the matching spawned event" do
    tell("type" => "spawned", "request_id" => 1, "pid" => 99)

    pid = client.spawn_mutant(mutant_id: "m", test_files: ["a_spec.rb"], log_paths: { out: "o" }, env: { "X" => "1" })

    expect(pid).to eq(99)
    expect(server_reader.next_message(1)).to include(
      "type" => "run", "mutant_id" => "m", "test_files" => ["a_spec.rb"], "env" => { "X" => "1" }
    )
  end

  it "raises SpawnFailed when the server could not fork the mutant" do
    tell("type" => "spawn_failed", "request_id" => 1, "reason" => "unknown")

    expect { client.spawn_mutant(mutant_id: "m", test_files: [], log_paths: {}) }
      .to raise_error(described_class::SpawnFailed, "unknown")
  end

  it "marks the server lost when it does not answer a run request" do
    stub_const("#{described_class}::SPAWN_TIMEOUT", 0.05)

    expect { client.spawn_mutant(mutant_id: "m", test_files: [], log_paths: {}) }
      .to raise_error(described_class::ServerLost, /did not answer/)
    expect(client).to be_lost
  end

  it "returns the status relayed for a pid, and nil while it still runs" do
    spawn_outstanding(5)
    expect(client.wait_exit(5, 0.05)).to be_nil

    tell("type" => "exited", "pid" => 5, "exitstatus" => nil, "termsig" => 9)

    expect(client.wait_exit(5, 1)).to be_signaled
  end

  it "keeps the exit of another pid for its own wait" do
    spawn_outstanding(5, 6)
    tell("type" => "exited", "pid" => 6, "exitstatus" => 0, "termsig" => nil)
    tell("type" => "exited", "pid" => 5, "exitstatus" => 1, "termsig" => nil)

    expect([client.wait_exit(5, 1).exitstatus, client.wait_exit(6, 1).exitstatus]).to eq([1, 0])
  end

  it "drops the exit of a pid that is not outstanding" do
    tell("type" => "exited", "pid" => 5, "exitstatus" => 0, "termsig" => nil)

    expect([client.wait_exit(5, 0.05), client.poll_any_exit]).to eq([nil, nil])
  end

  describe "forgetting a pid" do
    it "drops its outstanding registration so a server loss does not complete it" do
      spawn_outstanding(99)
      client.forget(99)
      server.close

      expect([client.poll_any_exit, client.lost?]).to eq([nil, true])
    end

    it "drops an exit that already arrived for it" do
      spawn_outstanding(5)
      tell("type" => "exited", "pid" => 5, "exitstatus" => 0, "termsig" => nil)
      client.forget(5)

      expect([client.poll_exit(5), client.poll_any_exit]).to eq([nil, nil])
    end

    it "drops an exit that arrives after it" do
      spawn_outstanding(5)
      client.forget(5)
      tell("type" => "exited", "pid" => 5, "exitstatus" => 0, "termsig" => nil)

      expect(client.poll_exit(5)).to be_nil
    end
  end

  describe "polling for the parallel scheduler" do
    it "returns a relayed exit without blocking and nil while the process runs" do
      spawn_outstanding(5)
      expect(client.poll_exit(5)).to be_nil

      tell("type" => "exited", "pid" => 5, "exitstatus" => 0, "termsig" => nil)

      expect(client.poll_exit(5)).to be_success
    end

    it "hands out relayed exits of any pid one at a time" do
      spawn_outstanding(5)
      tell("type" => "exited", "pid" => 5, "exitstatus" => 1, "termsig" => nil)

      pid, status = client.poll_any_exit

      expect([pid, status.exitstatus, client.poll_any_exit]).to eq([5, 1, nil])
    end

    it "completes outstanding processes as lost when the server is lost" do
      tell("type" => "spawned", "request_id" => 1, "pid" => 99)
      client.spawn_mutant(mutant_id: "m", test_files: [], log_paths: {})
      server.close

      pid, status = client.poll_any_exit

      expect([pid, status.lost?, client.lost?]).to eq([99, true, true])
    end

    it "reports an exit that spawning already buffered as a pending event" do
      tell("type" => "spawned", "request_id" => 1, "pid" => 5)
      tell("type" => "exited", "pid" => 5, "exitstatus" => 0, "termsig" => nil)
      expect(client.pending_events?).to be(false)

      client.spawn_mutant(mutant_id: "m", test_files: [], log_paths: {})
      expect(client.pending_events?).to be(true)

      client.poll_any_exit
      expect(client.pending_events?).to be(false)
    end

    it "reports an exit recorded for another pid as pending until it is polled" do
      spawn_outstanding(5, 6)
      tell("type" => "exited", "pid" => 6, "exitstatus" => 0, "termsig" => nil)
      client.wait_exit(5, 0.05)
      expect(client.pending_events?).to be(true)

      client.poll_exit(6)
      expect(client.pending_events?).to be(false)
    end

    it "does not report a lost server while it is connected" do
      client.poll_any_exit

      expect(client).not_to be_lost
    end

    it "exposes the connection to select on" do
      expect(client.io).to eq(sockets.first)
    end
  end

  describe "#abandon" do
    let(:client) { described_class.new(socket: sockets.first, pid: 4242) }

    it "closes the connection, kills and reaps the server and marks it lost" do
      allow(Process).to receive(:kill)
      allow(Process).to receive(:wait)

      client.abandon

      expect(Process).to have_received(:kill).with(:SIGKILL, 4242)
      expect(Process).to have_received(:wait).with(4242)
      expect([sockets.first.closed?, client.lost?]).to eq([true, true])
    end

    it "tolerates a server that is already gone, and a later shutdown" do
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

      expect { client.abandon }.not_to raise_error
      expect { client.shutdown }.not_to raise_error
    end

    it "kills the mutant processes the server left running" do
      allow(Process).to receive(:kill)
      allow(Process).to receive(:wait)
      spawn_outstanding(99)

      client.abandon

      expect(Process).to have_received(:kill).with(:SIGKILL, -99)
    end
  end

  it "kills the mutant processes outstanding when the connection drops" do
    allow(Process).to receive(:kill)
    spawn_outstanding(99)
    server.close

    client.poll_any_exit

    expect(Process).to have_received(:kill).with(:SIGKILL, -99)
  end

  it "tells the server to shut down and closes the socket" do
    client.shutdown

    expect(server_reader.next_message(1)).to eq("type" => "shutdown")
  end
end
