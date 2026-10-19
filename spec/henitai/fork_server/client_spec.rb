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

  it "returns the status relayed for a pid, and nil while it still runs" do
    expect(client.wait_exit(5, 0.05)).to be_nil

    tell("type" => "exited", "pid" => 5, "exitstatus" => nil, "termsig" => 9)

    expect(client.wait_exit(5, 1)).to be_signaled
  end

  it "keeps the exit of another pid for its own wait" do
    tell("type" => "exited", "pid" => 6, "exitstatus" => 0, "termsig" => nil)
    tell("type" => "exited", "pid" => 5, "exitstatus" => 1, "termsig" => nil)

    expect([client.wait_exit(5, 1).exitstatus, client.wait_exit(6, 1).exitstatus]).to eq([1, 0])
  end

  describe "polling for the parallel scheduler" do
    it "returns a relayed exit without blocking and nil while the process runs" do
      expect(client.poll_exit(5)).to be_nil

      tell("type" => "exited", "pid" => 5, "exitstatus" => 0, "termsig" => nil)

      expect(client.poll_exit(5)).to be_success
    end

    it "hands out relayed exits of any pid one at a time" do
      tell("type" => "exited", "pid" => 5, "exitstatus" => 1, "termsig" => nil)

      pid, status = client.poll_any_exit

      expect([pid, status.exitstatus, client.poll_any_exit]).to eq([5, 1, nil])
    end

    it "completes outstanding processes as killed when the server is lost" do
      tell("type" => "spawned", "request_id" => 1, "pid" => 99)
      client.spawn_mutant(mutant_id: "m", test_files: [], log_paths: {})
      server.close

      pid, status = client.poll_any_exit

      expect([pid, status.termsig, client.lost?]).to eq([99, 9, true])
    end

    it "does not report a lost server while it is connected" do
      client.poll_any_exit

      expect(client).not_to be_lost
    end

    it "exposes the connection to select on" do
      expect(client.io).to eq(sockets.first)
    end
  end

  it "tells the server to shut down and closes the socket" do
    client.shutdown

    expect(server_reader.next_message(1)).to eq("type" => "shutdown")
  end
end
