# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ForkServer::GroupTerminator, :aggregate_failures do
  let(:killer) { class_double(Henitai::ForkServer::GroupKiller, kill: nil) }
  let(:now) { [0.0] }
  let(:pauses) { [] }
  let(:terminator) do
    described_class.new(
      killer:,
      clock: ->(_clock_id) { now.first },
      pauser: lambda { |seconds|
        pauses << seconds
        now[0] += seconds
      }
    )
  end

  it "stops after SIGTERM when the process is gone" do
    allow(killer).to receive(:alive?).and_return(false)

    terminator.terminate(7)

    expect(killer).to have_received(:kill).with(7, :SIGTERM, leader: true).once
    expect(killer).not_to have_received(:kill).with(7, :SIGKILL, leader: true)
    expect(pauses).to be_empty
  end

  it "polls for the grace period, then escalates to SIGKILL" do
    allow(killer).to receive(:alive?).and_return(true)

    terminator.terminate(7)

    expect(killer).to have_received(:kill).with(7, :SIGKILL, leader: true).once
    expect(now.first).to be_within(0.05).of(3.0)
    expect(pauses.uniq).to eq([described_class::POLL_SECONDS])
  end

  it "does not escalate when the process leaves during the grace period" do
    allow(killer).to receive(:alive?).and_return(true, true, false)

    terminator.terminate(7)

    expect(killer).not_to have_received(:kill).with(7, :SIGKILL, leader: true)
    expect(pauses.size).to eq(2)
  end

  it "hands the leader flag to the killer and its probe" do
    allow(killer).to receive(:alive?).with(7, leader: false).and_return(false)

    terminator.terminate(7, leader: false)

    expect(killer).to have_received(:kill).with(7, :SIGTERM, leader: false)
  end

  it "uses the real clock and sleep by default" do
    allow(killer).to receive(:alive?).and_return(false)

    expect { described_class.new(killer:).terminate(7) }.not_to raise_error
  end
end
