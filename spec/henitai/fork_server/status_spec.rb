# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::ForkServer::Status do
  it "describes a normal exit" do
    status = described_class.new(exitstatus: 0, termsig: nil)

    expect([status.success?, status.signaled?, status.exitstatus]).to eq([true, false, 0])
  end

  it "reports a normal exit, but not a signal death, as exited" do
    expect([described_class.new(exitstatus: 1, termsig: nil).exited?,
            described_class.new(exitstatus: nil, termsig: 9).exited?]).to eq([true, false])
  end

  it "describes a failing exit" do
    expect(described_class.new(exitstatus: 1, termsig: nil).success?).to be(false)
  end

  it "describes a signal death" do
    status = described_class.new(exitstatus: nil, termsig: 9)

    expect([status.success?, status.signaled?, status.termsig]).to eq([false, true, 9])
  end

  it "marks a status synthesized for a lost server", :aggregate_failures do
    lost = described_class.lost

    expect([lost.lost?, lost.signaled?, lost.termsig]).to eq([true, true, 9])
    expect(described_class.new(exitstatus: nil, termsig: 9)).not_to be_lost
  end

  it "round-trips through an event" do
    status = described_class.from_event(described_class.new(exitstatus: nil, termsig: 15).to_event)

    expect([status.signaled?, status.termsig]).to eq([true, 15])
  end

  it "copies a Process::Status" do
    process_status = instance_double(Process::Status, exitstatus: 3, termsig: nil)

    expect(described_class.from_process_status(process_status).exitstatus).to eq(3)
  end
end
