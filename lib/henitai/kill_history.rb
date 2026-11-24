# frozen_string_literal: true

module Henitai
  # Counts, per test file, the mutants it killed so far in this run, so
  # {TestPrioritizer} can put proven killers first for the mutants still to
  # come. A progress observer behind the {ControlGate}: only final kills
  # count, never one a failed control reclassified.
  class KillHistory
    def initialize
      @kills = Hash.new(0)
    end

    def progress(_mutant, scenario_result: nil)
      return unless scenario_result&.status == :killed

      scenario_result.killing_tests.each { |file| @kills[file] += 1 }
    end

    # @return [Integer, Object] kills of +file+ (an expanded path), or
    #   +default+ when it killed nothing yet
    def fetch(file, default = nil)
      @kills.fetch(file, default)
    end
  end
end
