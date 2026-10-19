# frozen_string_literal: true

require "socket"
require "spec_helper"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe Henitai::ForkServer::Server, :aggregate_failures do
  let(:protocol) { Henitai::ForkServer::Protocol }
  let(:sockets) { UNIXSocket.pair }
  let(:parent) { sockets.first }
  let(:reader) { protocol::Reader.new(parent) }
  let(:launched) { [] }
  let(:killed) { [] }
  let(:exited) { [] }
  let(:launcher) do
    lambda do |request|
      raise KeyError, "unknown mutant" if request["mutant_id"] == "unknown"

      launched << request
      4242
    end
  end
  let(:boot) { -> {} }

  def build_server
    described_class.new(socket: sockets.last, boot:, launcher:, reaper: -> { exited.shift(exited.size) },
                        killer: ->(pid) { killed << pid })
  end

  def serve_in_thread
    thread = Thread.new { build_server.serve }
    yield
    thread.join(5)
  ensure
    thread&.kill
    sockets.each { |socket| socket.close unless socket.closed? }
  end

  it "announces readiness after booting and stops on shutdown" do
    serve_in_thread do
      expect(reader.next_message(5)).to eq("type" => "ready")
      parent.write(protocol.encode("type" => "shutdown"))
    end
  end

  context "when booting fails" do
    let(:boot) { -> { raise "no database" } }

    it "reports boot_failed with the reason and ends" do
      serve_in_thread do
        expect(reader.next_message(5)).to eq("type" => "boot_failed", "reason" => "RuntimeError: no database")
      end
    end
  end

  it "launches a requested mutant and relays how it ended" do
    serve_in_thread do
      reader.next_message(5)
      parent.write(protocol.encode("type" => "run", "request_id" => 7, "mutant_id" => "m1"))
      expect(reader.next_message(5)).to eq("type" => "spawned", "request_id" => 7, "pid" => 4242)

      exited << [4242, Henitai::ForkServer::Status.new(exitstatus: 1, termsig: nil)]
      expect(reader.next_message(5)).to eq("type" => "exited", "pid" => 4242, "exitstatus" => 1, "termsig" => nil)
      parent.write(protocol.encode("type" => "shutdown"))
    end
    expect(launched.map { |request| request["mutant_id"] }).to eq(["m1"])
  end

  it "answers spawn_failed when the launcher raises" do
    serve_in_thread do
      reader.next_message(5)
      parent.write(protocol.encode("type" => "run", "request_id" => 1, "mutant_id" => "unknown"))
      event = reader.next_message(5)

      expect([event["type"], event["request_id"], event["reason"]]).to eq(
        ["spawn_failed", 1, "KeyError: unknown mutant"]
      )
      parent.write(protocol.encode("type" => "shutdown"))
    end
  end

  it "kills live mutant process groups when the parent disappears" do
    serve_in_thread do
      reader.next_message(5)
      parent.write(protocol.encode("type" => "run", "request_id" => 1, "mutant_id" => "m1"))
      reader.next_message(5)
      parent.close
    end
    expect(killed).to eq([4242])
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
