# frozen_string_literal: true

module Henitai
  class SlotScheduler
    # Control jobs (ADR-19 §2): the unmutated method of a group whose first
    # detection a {ControlGate} is holding. A control job is not a mutant job:
    #
    # - it is spawned ahead of pending mutants, with its group's test files
    #   (no reselection);
    # - it runs as a local child (`spawn_local` when the integration is the
    #   fork-server runner, which registers the pid with the server runtime
    #   and applies a boot-inclusive timeout); the server never saw it;
    # - it is never retried, and it is neither a result nor progress;
    # - every terminal outcome -- exit, timeout, spawn failure -- reaches the
    #   listener once. A control interrupted by shutdown reports nothing: the
    #   gate's held detections are dropped with the run.
    #
    # Mixed into {SlotScheduler}; relies on its slot table and spawn helpers.
    module ControlSlots
      ControlJob = Struct.new(:key, :mutant, :test_files)

      def enqueue_control(key, mutant, test_files)
        control_jobs << ControlJob.new(key, mutant, test_files)
      end

      private

      def control_jobs = @control_jobs ||= []

      def spawn_control_into_slot(job)
        worker_index = slot_table.next_free_worker_index(worker_count)
        with_worker_slot(worker_index) do
          handle = spawn_control_child(job)
          timeout = handle.timeout || slot_timeout(job.mutant, job.test_files)
          register_slot(handle, job.mutant, worker_index, timeout, control_key: job.key)
        end
      rescue StandardError => e
        report_control(job.key, ScenarioExecutionResult.spawn_failure(e))
      end

      def spawn_control_child(job)
        spawner = integration.respond_to?(:spawn_local) ? :spawn_local : :spawn_mutant
        integration.public_send(spawner, mutant: job.mutant, test_files: job.test_files)
      end

      def complete_control(slot, wait_result)
        slot_table.delete(slot.slot_id)
        report_control(slot.control_key, integration.build_result(wait_result, slot.log_paths))
      end

      # The gate keeps only the control's verdict, never its output.
      def report_control(key, result)
        @control_listener&.control_finished(key, result)
        result.release_output! if result.respond_to?(:release_output!)
      end
    end
  end
end
