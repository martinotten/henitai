# frozen_string_literal: true

module Henitai
  # Holds a detected verdict back from the progress observers until a control
  # run has shown that the unmutated method passes the same tests (ADR-14,
  # ADR-19). Every verdict an observer sees is therefore final: the terminal,
  # the report checkpoints and the history never see a detection that a later
  # control would reclassify.
  #
  # One control runs per {ControlRun#group_key}; its outcome is memoized and
  # applied to every later detection of the group. A failing control
  # reclassifies the mutant and its scenario result as CompileError.
  #
  # The launcher starts a group's control. By default it runs synchronously
  # (linear execution); a scheduler passes its own launcher and reports the
  # outcome through {#control_finished} later, holding the detections until
  # then.
  class ControlGate
    attr_reader :stats

    def initialize(downstream:, control_run:, launcher: nil)
      @downstream = downstream
      @control_run = control_run
      @launcher = launcher || ->(key, mutant) { control_finished(key, control_run.run_for(mutant)) }
      @outcomes = {}
      @held = {}
      @stats = { verified: 0, failed: 0, reclassified: 0 }
    end

    def progress(mutant, scenario_result: nil)
      return deliver(mutant, scenario_result) unless @control_run.controllable?(mutant)

      key = @control_run.group_key(mutant)
      return release(mutant, scenario_result, @outcomes[key]) if @outcomes.key?(key)

      hold(key, mutant, scenario_result)
    end

    def control_finished(key, result)
      @outcomes[key] = result
      @stats[:verified] += 1
      @stats[:failed] += 1 unless @control_run.passed?(result)
      Array(@held.delete(key)).each { |mutant, scenario_result| release(mutant, scenario_result, result) }
    end

    # Discards every held detection, e.g. on shutdown; they re-execute in the
    # next run. @return [Integer] how many were dropped
    def drop_held
      count = @held.values.sum(&:size)
      @held.clear
      count
    end

    private

    def hold(key, mutant, scenario_result)
      first = !@held.key?(key)
      (@held[key] ||= []) << [mutant, scenario_result]
      @launcher.call(key, mutant) if first
    end

    def release(mutant, scenario_result, control_result)
      return deliver(mutant, scenario_result) if @control_run.passed?(control_result)

      @stats[:reclassified] += @control_run.reclassify([mutant], control_result)
      deliver(mutant, reclassified(scenario_result, mutant))
    end

    def reclassified(scenario_result, mutant)
      return scenario_result unless scenario_result.respond_to?(:reclassified)

      scenario_result.reclassified(status: mutant.status, status_reason: mutant.status_reason)
    end

    def deliver(mutant, scenario_result)
      @downstream&.progress(mutant, scenario_result:)
    end
  end
end
