# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Henitai::Integration::CappedLogSink do
  let(:file) { StringIO.new(String.new(encoding: Encoding::BINARY)) }
  let(:marker) { "\n[henitai] output truncated at 10 bytes\n" }

  def written
    file.string.b
  end

  it "passes writes below the cap through unchanged" do
    sink = described_class.new(file, 10)

    sink.write("abc")
    sink.write("de")

    expect(written).to eq("abcde".b)
  end

  it "cuts a write that crosses the cap at exactly cap bytes and appends the marker" do
    sink = described_class.new(file, 10)

    sink.write("abcdefgh")
    sink.write("ijklmnop")

    expect(written).to eq("abcdefghij#{marker}".b)
  end

  it "discards writes after the cap and emits the marker exactly once" do
    sink = described_class.new(file, 10)

    sink.write("abcdefghij")
    sink.write("more")
    sink.write("even more")

    expect(written).to eq("abcdefghij#{marker}".b)
  end

  it "appends the marker once when a write lands exactly on the cap" do
    sink = described_class.new(file, 10)

    sink.write("abcdef")
    sink.write("ghij")
    sink.write("tail")

    expect(written).to eq("abcdefghij#{marker}".b)
  end

  it "cuts multibyte binary chunks by bytes rather than characters" do
    sink = described_class.new(file, 5)
    chunk = "\xE2\x82\xAC\xE2\x82\xAC\xE2\x82\xAC".b # three 3-byte sequences

    sink.write(chunk)

    expect(written).to eq(
      "\xE2\x82\xAC\xE2\x82".b + "\n[henitai] output truncated at 5 bytes\n".b
    )
  end
end
