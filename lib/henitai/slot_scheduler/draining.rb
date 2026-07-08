# frozen_string_literal: true

module Henitai
  class SlotScheduler
    # Drain/timeout state machine for in-flight slots.
    #
    # A slot enters the draining state either when it exceeds its timeout
    # ({#check_timeouts}) or when a shutdown is requested
    # ({#interrupt_active_slots}). {#drain_draining_slots} then performs the
    # two-phase SIGTERM/SIGKILL broadcast and the final blocking reap.
    #
    # Mixed into {SlotScheduler}; relies on its slot table, +integration+,
    # +progress_reporter+, +wakeup+ and the {ProcessControl} primitives.
    module Draining
      # Per-slot timeout check. Must be called after reap_all_completed_children
      # so that naturally-exited processes are already removed from slots.
      def check_timeouts
        now = monotonic_time
        slots.each_value do |slot|
          next if slot.draining
          next unless now >= slot.started_at_monotonic + slot.timeout

          # Final targeted reap: if the child already exited, classify it normally.
          pid, status = wnohang_reap(slot.pid)
          if pid
            complete_slot(pid, status)
          else
            slot.forced_outcome = :timeout
            slot.draining = true
          end
        end
      end

      def draining_slots?
        slots.any? { |_, slot| slot.draining }
      end

      # Two-phase broadcast cleanup for all slots that are in draining state.
      #
      # Precision rule: before signalling, do one final WNOHANG pass to catch
      # processes that exited naturally in the window between check_timeouts and
      # now. If SIGTERM gets ESRCH, the process is already gone — we must not
      # force-label those as :timeout.
      def drain_draining_slots
        draining = draining_slots
        return if draining.empty?

        prune_raced_draining_slots(draining)

        return if draining.empty?

        broadcast_term(draining)
        wait_for_drain_window
        signal_draining_slots(draining)
        reap_and_remove_draining(draining)
      end

      def interrupt_active_slots
        slots.each_value do |slot|
          next if slot.draining

          slot.forced_outcome = :interrupted
          slot.draining = true
        end
      end

      private

      def draining_slots
        slots.select { |_, slot| slot.draining }
      end

      def prune_raced_draining_slots(draining)
        draining.reject! do |_, slot|
          pid, status = wnohang_reap(slot.pid)
          next false unless pid

          complete_slot(pid, status)
          true
        end
      end

      def wait_for_drain_window
        wakeup&.wait(PROCESS_DRAIN_WINDOW)
        wakeup&.drain
      end

      def signal_draining_slots(draining)
        draining.each_value { |slot| signal_process_group(slot.pid, :SIGKILL) }
      end

      def broadcast_term(draining)
        now = monotonic_time
        draining.each_value do |slot|
          slot.term_sent_at_monotonic = now
          signal_process_group(slot.pid, :SIGTERM)
        end
      end

      # After SIGKILL window: blocking reap each slot, then build its result.
      #
      # Interrupted slots are cleaned up but produce no result — the scheduler
      # is shutting down and does not emit verdicts for in-flight mutants.
      #
      # For timeout slots: a real exit status only wins if observed before any
      # parent signal was sent. Once SIGTERM has been dispatched, the forced
      # outcome is authoritative — a child handling SIGTERM and exiting 0 must
      # not be misclassified as :survived.
      def reap_and_remove_draining(draining)
        draining.each_value { |slot| reap_and_finalize_slot(slot) }
      end

      # One last WNOHANG before blocking: catches processes that exited
      # between SIGKILL and here.
      def reap_and_finalize_slot(slot)
        _, final_status = wnohang_reap(slot.pid)
        reap_pid(slot.pid) unless final_status

        pid_to_slot.delete(slot.pid)
        slots.delete(slot.slot_id)
        Integration::SchedulerDiagnostics.child_ended(slot.pid)

        return if slot.forced_outcome == :interrupted

        record_drain_result(slot, final_status)
      end

      def record_drain_result(slot, final_status)
        result = build_drain_result(slot, final_status)
        slot.mutant.status = result.status
        results << result
        progress_reporter&.progress(slot.mutant, scenario_result: result)
      end

      # Choose result: use real exit status only if observed before any parent
      # signal was sent. After SIGTERM, the forced outcome is authoritative.
      def build_drain_result(slot, final_status)
        if final_status&.exited? && slot.term_sent_at_monotonic.nil?
          integration.build_result(final_status, slot.log_paths)
        else
          integration.build_result(slot.forced_outcome || :timeout, slot.log_paths)
        end
      end
    end
  end
end
