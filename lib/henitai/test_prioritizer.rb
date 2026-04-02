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

      history_value = history_value_for(history, test)

      case history_value
      when Integer
        history_value
      when Hash
        history_value.fetch(:kills, history_value.fetch("kills", 0)).to_i
      else
        history_value.to_i
      end
    end

    def history_value_for(history, test)
      history_key_candidates(test).each do |key|
        value = history.fetch(key, nil)
        return value unless value.nil?
      end

      0
    end

    def history_key_candidates(test)
      key = test.to_s
      candidates = [key, File.expand_path(key), relative_history_key(key)]
      candidates.compact.uniq
    rescue StandardError
      [key]
    end

    def relative_history_key(path)
      pathname = Pathname.new(path)
      return unless pathname.absolute?

      pathname.relative_path_from(Pathname.pwd).to_s
    rescue StandardError
      nil
    end
  end
end
