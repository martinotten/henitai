# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SlotScheduler::SlotTable do
  subject(:table) { described_class.new }

  def build_slot(slot_id:, pid: 100 + slot_id, worker_index: slot_id, draining: false)
    Henitai::SlotScheduler::Slot.new(
      slot_id, nil, pid, 0.0, 5.0, nil, 0, draining, nil, nil, worker_index
    )
  end

  describe "#add, #fetch and #delete" do
    it "starts empty" do
      expect(table).to be_empty
    end

    it "keys a slot by its slot_id", :aggregate_failures do
      slot = build_slot(slot_id: 7)

      table.add(slot)

      expect(table.fetch(7)).to be(slot)
      expect(table).not_to be_empty
      expect(table.size).to eq(1)
    end

    it "answers nil for a slot_id it never held" do
      expect(table.fetch(7)).to be_nil
    end

    it "removes a slot and answers it", :aggregate_failures do
      slot = build_slot(slot_id: 7)
      table.add(slot)

      expect(table.delete(7)).to be(slot)
      expect(table).to be_empty
    end

    it "tolerates deleting a slot_id it does not hold" do
      expect(table.delete(7)).to be_nil
    end

    it "replaces rather than duplicates when the same slot_id is added twice" do
      table.add(build_slot(slot_id: 7))
      replacement = build_slot(slot_id: 7, pid: 999)

      table.add(replacement)

      expect(table.size).to eq(1)
    end
  end

  describe "pid indexing" do
    it "answers the slot_id a pid was registered under" do
      table.register_pid(500, 7)

      expect(table.release_pid(500)).to eq(7)
    end

    # A pid may only be claimed once: the reap path relies on release_pid
    # returning nil the second time so two threads cannot both finalize a slot.
    it "answers nil on a second release of the same pid" do
      table.register_pid(500, 7)
      table.release_pid(500)

      expect(table.release_pid(500)).to be_nil
    end

    it "answers nil for a pid never registered" do
      expect(table.release_pid(500)).to be_nil
    end

    it "reports whether a pid is currently registered", :aggregate_failures do
      table.register_pid(500, 7)

      expect(table.pid_registered?(500)).to be(true)
      expect(table.pid_registered?(501)).to be(false)
    end

    # A flaky retry keeps the slot and its id but respawns under a new pid, so
    # the reverse index has to accept re-pointing without touching the slot.
    it "re-points an existing slot_id at a new pid", :aggregate_failures do
      slot = build_slot(slot_id: 7)
      table.add(slot)
      table.register_pid(500, 7)
      table.release_pid(500)
      table.register_pid(600, 7)

      expect(table.release_pid(600)).to eq(7)
      expect(table.fetch(7)).to be(slot)
    end

    it "does not remove the slot itself when its pid is released" do
      slot = build_slot(slot_id: 7)
      table.add(slot)
      table.register_pid(500, 7)

      table.release_pid(500)

      expect(table.fetch(7)).to be(slot)
    end
  end

  describe "#next_slot_id!" do
    it "starts at 0 and increments monotonically across calls" do
      expect([table.next_slot_id!, table.next_slot_id!, table.next_slot_id!]).to eq([0, 1, 2])
    end

    # Ids are never recycled, unlike worker indices: that is what makes them
    # safe as hash keys across a retry.
    it "does not reuse an id whose slot has been deleted" do
      first = table.next_slot_id!
      table.add(build_slot(slot_id: first))
      table.delete(first)

      expect(table.next_slot_id!).to eq(1)
    end
  end

  describe "#next_free_worker_index" do
    it "returns 0 when no slots are in use" do
      expect(table.next_free_worker_index(2)).to eq(0)
    end

    it "returns the smallest index not held by a live slot" do
      table.add(build_slot(slot_id: 0, worker_index: 0))
      table.add(build_slot(slot_id: 1, worker_index: 2))

      expect(table.next_free_worker_index(4)).to eq(1)
    end

    it "reuses an index freed by a deleted slot" do
      table.add(build_slot(slot_id: 0, worker_index: 0))
      table.add(build_slot(slot_id: 1, worker_index: 1))
      table.delete(0)

      expect(table.next_free_worker_index(2)).to eq(0)
    end

    # The fallback branch: nothing below worker_count is free, so the index
    # count is used instead of handing out a duplicate.
    it "does not treat worker_count itself as a free index" do
      [0, 1, 5].each_with_index do |worker_index, slot_id|
        table.add(build_slot(slot_id: slot_id, worker_index: worker_index))
      end

      expect(table.next_free_worker_index(2)).to eq(3)
    end

    it "falls back past worker_count when every index below it is taken" do
      table.add(build_slot(slot_id: 0, worker_index: 0))
      table.add(build_slot(slot_id: 1, worker_index: 1))

      expect(table.next_free_worker_index(2)).to eq(2)
    end
  end

  describe "draining queries" do
    it "reports no draining slots for an empty table", :aggregate_failures do
      expect(table.any_draining?).to be(false)
      expect(table.draining).to eq({})
    end

    it "reports no draining slots when every slot is live", :aggregate_failures do
      table.add(build_slot(slot_id: 0))

      expect(table.any_draining?).to be(false)
      expect(table.draining).to eq({})
    end

    it "selects only the draining slots, keyed by slot_id", :aggregate_failures do
      live = build_slot(slot_id: 0)
      draining = build_slot(slot_id: 1, draining: true)
      table.add(live)
      table.add(draining)

      expect(table.any_draining?).to be(true)
      expect(table.draining).to eq({ 1 => draining })
    end
  end

  describe "#each_value" do
    it "yields every slot in insertion order" do
      first = build_slot(slot_id: 0)
      second = build_slot(slot_id: 1)
      table.add(first)
      table.add(second)

      expect(table.each_value.to_a).to eq([first, second])
    end

    it "returns an enumerator when called without a block" do
      expect(table.each_value).to be_a(Enumerator)
    end
  end
end
