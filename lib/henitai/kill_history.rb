# frozen_string_literal: true

module Henitai
  # Counts, per test file, the mutants it killed so far in this run, so
  # {TestPrioritizer} can put proven killers first for the mutants still to
  # come. A progress observer behind the {ControlGate}: only final kills
  # count, never one a failed control reclassified.
  #
  # It also remembers which test file was running when a child timed out, per
  # subject: a file that hung for one mutant of a subject is probably the
  # hang for the others, so the prioritizer runs it last.
  class KillHistory
    def initialize
      @kills = Hash.new(0)
      @hung = {}
    end

    def progress(mutant, scenario_result: nil)
      case scenario_result&.status
      when :killed then count_kills(scenario_result)
      when :timeout then remember_hang(mutant, scenario_result)
      end
    end

    # @return [Integer, Object] kills of +file+ (an expanded path), or
    #   +default+ when it killed nothing yet
    def fetch(file, default = nil)
      @kills.fetch(file, default)
    end

    # @return [Boolean] whether +file+ hung for a mutant of the same subject
    def hung?(mutant, file)
      key = subject_key(mutant)
      return false unless key && file

      @hung.key?([key, File.expand_path(file)])
    end

    private

    def count_kills(scenario_result)
      scenario_result.killing_tests.each { |file| @kills[file] += 1 }
    end

    def remember_hang(mutant, scenario_result)
      key = subject_key(mutant)
      hanging_test = scenario_result.hanging_test if scenario_result.respond_to?(:hanging_test)
      return unless key && hanging_test

      @hung[[key, File.expand_path(hanging_test)]] = true
    end

    def subject_key(mutant)
      subject = mutant.subject if mutant.respond_to?(:subject)
      subject.expression if subject.respond_to?(:expression)
    end
  end
end
