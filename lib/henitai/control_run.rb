# frozen_string_literal: true

module Henitai
  # Verifies that the activation path itself does not break a subject's tests.
  #
  # For every subject and test-file set with a detected verdict (Killed,
  # Timeout, RuntimeError) the unmutated method is injected through the same
  # activation and fork path, against the same test files. The tests must
  # pass. If they do not, injecting the method is what made them fail -- a
  # lost constant scope, `super` or `yield` inside `define_method`, a rebuilt
  # parameter list -- so none of the group's detections can be credited to
  # their mutations. They are reclassified as CompileError with the control's
  # outcome as reason. {ControlGate} decides when a control runs: at the
  # group's first detection (ADR-19); the scheduler runs it as a control job
  # (`SlotScheduler::ControlSlots`, ADR-20).
  #
  # Verdicts reused from history are left alone: they were not produced by
  # this run's activation.
  class ControlRun
    DETECTED = %i[killed timeout runtime_error].freeze

    # True for a verdict this run's activation produced and a control can
    # check: a detection with the original node at hand. Reused verdicts and
    # activation-recipe stubs (no original node) are not controllable.
    def controllable?(mutant)
      DETECTED.include?(mutant.status) && !from_cache?(mutant) && original_node?(mutant)
    end

    # Detections sharing a key share one control run.
    def group_key(mutant) = [mutant.subject, test_files(mutant)]

    def passed?(result) = result.status == :survived

    # The unmutated method as a mutant the activation path can inject.
    def control_mutant(mutant)
      node = mutant.original_node
      Mutant.new(subject: mutant.subject, operator: "Control", nodes: { original: node, mutated: node },
                 description: "unmutated control", location: mutant.location)
    end

    # The test files a group's control runs against: the detection's own.
    def test_files(mutant)
      Array(mutant.covered_by).sort
    end

    # @return [Integer] the number of reclassified mutants
    def reclassify(detected, result)
      reason = reason_for(result)
      detected.each do |mutant|
        mutant.status = :compile_error
        mutant.status_reason = reason
      end
      detected.size
    end

    private

    def from_cache?(mutant) = mutant.respond_to?(:from_cache?) && mutant.from_cache?

    def original_node?(mutant) = mutant.respond_to?(:original_node) && !mutant.original_node.nil?

    def reason_for(result)
      "control run failed: the unmutated method fails its tests when injected " \
        "(#{[result.status, result.status_reason].compact.join(': ')})"
    end
  end
end
