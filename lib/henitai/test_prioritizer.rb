# frozen_string_literal: true

module Henitai
  # Orders test files so previously effective tests run first.
  #
  # Primary key: kill-history count (a test that killed neighbouring mutants
  # probably kills this one). Tiebreaker: measured per-test-file runtime,
  # ascending, so the first kill costs as little wall-clock as possible.
  # Untimed tests sort after timed ones by original inventory order; with no
  # timing source at all the ordering is exactly the historical behavior.
  class TestPrioritizer
    # @param timing_source [#call, nil] returns a Hash of test file path to
    #   wall-clock seconds; resolved lazily on first sort.
    def initialize(timing_source: nil)
      @timing_source = timing_source
    end

    def sort(tests, _mutant, history)
      Array(tests).each_with_index.sort_by do |test, index|
        [-history_count(history, test), runtime(test), index]
      end.map(&:first)
    end

    private

    def runtime(test)
      durations = timing_durations
      history_key_candidates(test).each do |key|
        value = durations[key]
        return value.to_f unless value.nil?
      end

      Float::INFINITY
    end

    def timing_durations
      @timing_durations ||= @timing_source&.call || {}
    end

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
