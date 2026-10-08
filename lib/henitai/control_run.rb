# frozen_string_literal: true

module Henitai
  # Verifies, after execution, that the activation path itself does not break
  # a subject's tests.
  #
  # For every subject with a detected verdict (Killed, Timeout, RuntimeError)
  # the unmutated method is injected through the same activation and fork
  # path, against the same test files. The tests must pass. If they do not,
  # injecting the method is what made them fail -- a lost constant scope,
  # `super` or `yield` inside `define_method`, a rebuilt parameter list -- so
  # none of that subject's detections can be credited to its mutations. They
  # are reclassified as CompileError with the control's outcome as reason.
  #
  # Verdicts reused from history are left alone: they were not produced by
  # this run's activation.
  class ControlRun
    DETECTED = %i[killed timeout runtime_error].freeze

    # @param timeout_for [#call] test files -> timeout in seconds
    def initialize(integration:, timeout_for:)
      @integration = integration
      @timeout_for = timeout_for
    end

    # @return [Hash] verified:, failed: subjects; reclassified: mutants
    def verify(mutants)
      stats = { verified: 0, failed: 0, reclassified: 0 }
      detected_groups(mutants).each_value do |detected|
        stats[:verified] += 1
        result = run_control(detected.first)
        next if result.status == :survived

        stats[:failed] += 1
        stats[:reclassified] += reclassify(detected, result)
      end
      stats
    end

    private

    def detected_groups(mutants)
      Array(mutants)
        .select { |mutant| DETECTED.include?(mutant.status) && !mutant.from_cache? && mutant.original_node }
        .group_by { |mutant| [mutant.subject, test_files(mutant)] }
    end

    def run_control(mutant)
      files = test_files(mutant)
      @integration.run_mutant(mutant: control_for(mutant), test_files: files, timeout: @timeout_for.call(files))
    end

    def control_for(mutant)
      node = mutant.original_node
      Mutant.new(subject: mutant.subject, operator: "Control", nodes: { original: node, mutated: node },
                 description: "unmutated control", location: mutant.location)
    end

    def reclassify(detected, result)
      reason = "control run failed: the unmutated method fails its tests when injected " \
               "(#{[result.status, result.status_reason].compact.join(': ')})"
      detected.each do |mutant|
        mutant.status = :compile_error
        mutant.status_reason = reason
      end
      detected.size
    end

    def test_files(mutant)
      Array(mutant.covered_by).sort
    end
  end
end
