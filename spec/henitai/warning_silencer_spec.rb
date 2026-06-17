# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::WarningSilencer do
  it "discards warnings written to $stderr inside the block" do
    expect do
      described_class.silence { warn "noisy third-party warning" }
    end.not_to output.to_stderr
  end

  it "yields to the block and lets it run" do
    ran = false

    described_class.silence { ran = true }

    expect(ran).to be(true)
  end

  it "restores the original $stderr after the block returns" do
    original = $stderr

    described_class.silence { :noop }

    expect($stderr).to be(original)
  end

  it "restores $stderr even when the block raises" do
    original = $stderr
    begin
      described_class.silence { raise "boom" }
    rescue RuntimeError
      # expected; we only care that the ensure restored $stderr
    end

    expect($stderr).to be(original)
  end
end
