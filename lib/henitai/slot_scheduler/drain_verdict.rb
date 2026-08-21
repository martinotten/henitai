# frozen_string_literal: true

module Henitai
  class SlotScheduler
    # Chooses the verdict for a slot that went through the drain path.
    #
    # The rule: a real exit status only wins if the process exited *before* any
    # parent signal was sent. Once SIGTERM has been dispatched, the forced
    # outcome is authoritative — a child that traps SIGTERM and exits 0 would
    # otherwise be recorded as `:survived`, turning a timeout into a false
    # survivor and inflating the survivor list.
    #
    # `:timeout` is the fallback when nothing forced the outcome, because the
    # only way into this path without a forced outcome is a deadline breach.
    class DrainVerdict
      def initialize(integration:)
        @integration = integration
      end

      def build(slot, final_status)
        if final_status&.exited? && slot.term_sent_at_monotonic.nil?
          @integration.build_result(final_status, slot.log_paths)
        else
          @integration.build_result(slot.forced_outcome || :timeout, slot.log_paths)
        end
      end
    end
  end
end
