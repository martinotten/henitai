# frozen_string_literal: true

module Henitai
  class SlotScheduler
    # The slot table for one parallel run: live slots by id, the pid -> slot_id
    # reverse index, and the slot-id sequence.
    #
    # Two indexes rather than one because the two lookups have different
    # lifetimes. A slot survives a flaky retry and keeps its id, but its pid
    # changes with every respawn, so the reverse index is rebuilt while the
    # forward entry stays put.
    class SlotTable
      def initialize
        @slots = {}
        @pid_to_slot = {}
        @next_slot_id = 0
      end

      def add(slot)
        @slots[slot.slot_id] = slot
      end

      def delete(slot_id)
        @slots.delete(slot_id)
      end

      def fetch(slot_id)
        @slots[slot_id]
      end

      def empty? = @slots.empty?
      def size = @slots.size
      def each_value(&) = @slots.each_value(&)

      def register_pid(pid, slot_id)
        @pid_to_slot[pid] = slot_id
      end

      # Removes the mapping and answers the slot id it held, so a reap is a
      # single operation: a pid can only be claimed once.
      def release_pid(pid)
        @pid_to_slot.delete(pid)
      end

      def pid_registered?(pid) = @pid_to_slot.key?(pid)

      # Monotonic and never reused. Freed worker indices are recycled; slot ids
      # are not, which is what makes them safe as hash keys across retries.
      def next_slot_id!
        id = @next_slot_id
        @next_slot_id += 1
        id
      end

      # Smallest index in 0...worker_count not held by a live slot, so
      # concurrently-running children always see distinct values and freed
      # indices are reused. Slot ids themselves grow monotonically and are
      # unsuitable as a resource token.
      #
      # The `|| used.size` fallback covers a table already holding at least
      # worker_count slots — reachable when a retry respawns into a table that
      # a concurrent fill has since topped up.
      def next_free_worker_index(worker_count)
        used = @slots.each_value.map(&:worker_index)
        (0...worker_count).find { |index| !used.include?(index) } || used.size
      end

      def draining
        @slots.select { |_, slot| slot.draining }
      end

      def any_draining?
        @slots.any? { |_, slot| slot.draining }
      end
    end
  end
end
