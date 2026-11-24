# frozen_string_literal: true

require_relative "kill_history/store"

module Henitai
  # Counts, per test file, the mutants it killed so far in this run, so
  # {TestPrioritizer} can put proven killers first for the mutants still to
  # come. A progress observer behind the {ControlGate}: only final kills
  # count, never one a failed control reclassified.
  #
  # It also remembers which test file was running when a child timed out, per
  # subject: a file that hung for one mutant of a subject is probably the
  # hang for the others, so the prioritizer runs it last.
  #
  # Both are persisted in `henitai_test_order.json` (see {Store}): the next run
  # starts from the loaded kills and hangs. A file that killed in this run
  # gets this run's count saved; other files keep their loaded count.
  class KillHistory
    FILE_NAME = "henitai_test_order.json"

    # @return [KillHistory] seeded from +path+; empty when the file is missing
    def self.load(path)
      snapshot = Store.read(path)
      new(loaded_kills: snapshot.kills, loaded_hangs: snapshot.hangs)
    end

    def initialize(loaded_kills: {}, loaded_hangs: {})
      @loaded_kills = loaded_kills
      @run_kills = Hash.new(0)
      @hung = {}
      loaded_hangs.each { |subject, files| files.each { |file| @hung[[subject, file]] = true } }
    end

    # Saves the kills and hangs to +path+, creating its directory.
    def write(path)
      Store.write(path, kills: @loaded_kills.merge(@run_kills), hangs: hangs_by_subject)
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
      return default unless @loaded_kills.key?(file) || @run_kills.key?(file)

      @loaded_kills.fetch(file, 0) + @run_kills.fetch(file, 0)
    end

    # @return [Boolean] whether +file+ hung for a mutant of the same subject
    def hung?(mutant, file)
      key = subject_key(mutant)
      return false unless key && file

      @hung.key?([key, File.expand_path(file)])
    end

    private

    def count_kills(scenario_result)
      scenario_result.killing_tests.each { |file| @run_kills[file] += 1 }
    end

    def hangs_by_subject
      @hung.keys.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
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
