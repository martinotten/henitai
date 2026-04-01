# frozen_string_literal: true

module Henitai
  # Orders test files so previously effective tests run first.
  class TestPrioritizer
    def sort(tests, _mutant, history)
      Array(tests).each_with_index.sort_by do |test, index|
        [-history_count(history, test), index]
      end.map(&:first)
    end

    private

    def history_count(history, test)
      return 0 unless history.respond_to?(:fetch)

      history_value = history.fetch(test, 0)

      case history_value
      when Integer
        history_value
      when Hash
        history_value.fetch(:kills, history_value.fetch("kills", 0)).to_i
      else
        history_value.to_i
      end
    end
  end
end
