# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SignalDeferral do
  def deliver(signal)
    Process.kill(signal, Process.pid)
    sleep 0.05
  end

  it "lets the block finish, then re-sends a signal that arrived during it", :aggregate_failures do
    resent = []
    finished = false

    described_class.call(resend: ->(signal) { resent << signal }) do
      deliver(:TERM)
      finished = true
    end

    expect(finished).to be(true)
    expect(resent).to eq(["TERM"])
  end

  it "re-sends only the first of several signals" do
    resent = []

    described_class.call(resend: ->(signal) { resent << signal }) do
      deliver(:HUP)
      deliver(:INT)
    end

    expect(resent).to eq(["HUP"])
  end

  it "re-sends nothing when no signal arrived" do
    resent = []

    described_class.call(resend: ->(signal) { resent << signal }) { :done }

    expect(resent).to eq([])
  end

  it "restores the previous handlers" do
    previous = Signal.trap("HUP", "IGNORE")
    described_class.call(resend: ->(_signal) {}) { :done }

    expect(Signal.trap("HUP", previous)).to eq("IGNORE")
  end

  it "returns the block's value" do
    expect(described_class.call(resend: ->(_signal) {}) { :value }).to eq(:value)
  end
end
