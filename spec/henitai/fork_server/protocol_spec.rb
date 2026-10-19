# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ForkServer::Protocol, :aggregate_failures do
  let(:pair) { IO.pipe }
  let(:reader) { described_class::Reader.new(pair.first) }

  after { pair.each { |io| io.close unless io.closed? } }

  it "encodes one JSON message per line" do
    expect(described_class.encode("type" => "ready")).to eq(%({"type":"ready"}\n))
  end

  it "reads consecutive messages written in one chunk" do
    pair.last.write(described_class.encode("a" => 1) + described_class.encode("b" => 2))

    expect([reader.next_message(1), reader.next_message(1)]).to eq([{ "a" => 1 }, { "b" => 2 }])
  end

  it "waits for a message split across writes" do
    pair.last.write(%({"a":))
    expect(reader.next_message(0.05)).to eq(described_class::Reader::TIMEOUT)

    pair.last.write("1}\n")
    expect(reader.next_message(1)).to eq("a" => 1)
  end

  it "knows whether a whole message is already buffered" do
    pair.last.write([described_class.encode("a" => 1), described_class.encode("b" => 2), %({"c":)].join)
    expect(reader.buffered_message?).to be(false)

    reader.next_message(1)
    expect(reader.buffered_message?).to be(true)

    reader.next_message(1)
    expect(reader.buffered_message?).to be(false)
  end

  it "returns nil at end of stream" do
    pair.last.close

    expect(reader.next_message(1)).to be_nil
  end
end
