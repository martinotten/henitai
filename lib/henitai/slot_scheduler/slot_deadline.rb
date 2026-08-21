# frozen_string_literal: true

module Henitai
  class SlotScheduler
    # Seconds left before a slot is due, for the scheduler's event-wait budget.
    #
    # A live slot is due at `started_at + timeout`. A draining slot is due at
    # `term_sent_at + drain_window` instead: once SIGTERM has gone out, the only
    # remaining question is how long to wait before escalating to SIGKILL.
    class SlotDeadline
      def initialize(drain_window:)
        @drain_window = drain_window
      end

      def remaining(slot, now)
        # Invariant: drain_draining_slots runs (and removes draining slots)
        # before the event wait, so this never observes a draining slot whose
        # SIGTERM has not been sent. Guarded defensively against a future
        # ordering change: an unsignalled draining slot is due now.
        return 0.0 if slot.draining && slot.term_sent_at_monotonic.nil?

        remaining = deadline_for(slot) - now
        remaining.positive? ? remaining : 0.0
      end

      private

      def deadline_for(slot)
        if slot.draining
          slot.term_sent_at_monotonic + @drain_window
        else
          slot.started_at_monotonic + slot.timeout
        end
      end
    end
  end
end
