# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SlotScheduler::SlotDeadline do
  subject(:deadline) { described_class.new(drain_window: drain_window) }

  # A distinctive value rather than PROCESS_DRAIN_WINDOW: this asserts the
  # injected window is the one used, not that two copies of the same constant
  # happen to agree.
  let(:drain_window) { 0.75 }

  def build_slot(started_at:, timeout:, draining: false, term_sent_at: nil)
    Henitai::SlotScheduler::Slot.new(
      1, nil, 12, started_at, timeout, nil, 0, draining, term_sent_at, :timeout, 0
    )
  end

  it "treats a draining slot with no SIGTERM timestamp as due immediately" do
    slot = build_slot(started_at: 0.0, timeout: 5.0, draining: true)

    expect(deadline.remaining(slot, 0.0)).to be(0.0)
  end

  it "measures from the SIGTERM timestamp once SIGTERM has been sent" do
    slot = build_slot(started_at: 0.0, timeout: 5.0, draining: true, term_sent_at: 1.0)

    expect(deadline.remaining(slot, 1.0)).to be_within(1e-9).of(drain_window)
  end

  it "ignores the slot's own timeout while draining" do
    # started_at + timeout would still leave 4.0s; the drain window is what
    # governs a slot that has already been signalled.
    slot = build_slot(started_at: 0.0, timeout: 5.0, draining: true, term_sent_at: 0.5)

    expect(deadline.remaining(slot, 1.0)).to be_within(1e-9).of(0.25)
  end

  it "computes remaining time from started_at_monotonic + timeout for a live slot" do
    slot = build_slot(started_at: 10.0, timeout: 5.0)

    expect(deadline.remaining(slot, 12.0)).to eq(3.0)
  end

  it "clips a negative remaining time to 0.0 for a live slot past its deadline" do
    slot = build_slot(started_at: 10.0, timeout: 5.0)

    expect(deadline.remaining(slot, 20.0)).to eq(0.0)
  end

  it "returns 0.0, not a negative, for a slot due exactly now" do
    slot = build_slot(started_at: 10.0, timeout: 5.0)

    expect(deadline.remaining(slot, 15.0)).to eq(0.0)
  end
end
