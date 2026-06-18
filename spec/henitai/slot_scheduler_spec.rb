# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SlotScheduler do
  def build_scheduler
    described_class.new(
      integration: nil,
      config: nil,
      progress_reporter: nil,
      options: {},
      host: nil
    )
  end

  describe "#remaining_slot_timeout draining invariant" do
    it "treats a draining slot with no SIGTERM timestamp as due immediately" do
      slot = Henitai::SlotScheduler::Slot.new(
        1, nil, 12, 0.0, 5.0, nil, 0, true, nil, :timeout
      )

      expect(build_scheduler.send(:remaining_slot_timeout, slot, 0.0)).to eq(0.0)
    end

    it "uses the drain window once SIGTERM has been sent" do
      slot = Henitai::SlotScheduler::Slot.new(
        1, nil, 12, 0.0, 5.0, nil, 0, true, 1.0, :timeout
      )
      window = Henitai::SlotScheduler::PROCESS_DRAIN_WINDOW

      expect(build_scheduler.send(:remaining_slot_timeout, slot, 1.0)).to be_within(1e-9).of(window)
    end
  end
end
