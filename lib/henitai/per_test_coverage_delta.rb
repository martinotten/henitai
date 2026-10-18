# frozen_string_literal: true

module Henitai
  # Computes which source lines a test executed in one file, from two
  # cumulative +Coverage.peek_result+ entries (before and after the test).
  #
  # Line coverage alone misses endless methods (+def x = expr+): calling
  # one never increments any line count, so their body lines would only be
  # attributed to the test that loaded the file. When method coverage is
  # available, every called method also contributes its +def+ line and the
  # lines inside its range that line coverage does not track.
  class PerTestCoverageDelta
    def executed_lines(current, previous)
      (counted_lines(current, previous) | called_method_lines(current, previous)).sort
    end

    private

    # Count-delta attribution: a line belongs to every test whose run
    # incremented its cumulative count, not just the first toucher. This keeps
    # the per-test map a complete over-approximation of reachability — the
    # soundness precondition for survivor verdict reuse (ADR-11).
    def counted_lines(current, previous)
      previous_counts = line_counts(previous)
      line_counts(current).each_with_index.filter_map do |count, index|
        index + 1 if count.to_i > previous_counts.fetch(index, 0).to_i
      end
    end

    def called_method_lines(current, previous)
      counts = line_counts(current)
      previous_calls = method_counts(previous)
      method_counts(current).flat_map do |key, calls|
        next [] unless calls.to_i > previous_calls.fetch(key, 0).to_i

        untracked_method_lines(key, counts)
      end
    end

    def untracked_method_lines(key, counts)
      first_line = key[2]
      last_line = key[4]
      (first_line..last_line).select do |line|
        line == first_line || counts[line - 1].nil?
      end
    end

    def line_counts(file_coverage)
      return Array(file_coverage) unless file_coverage.is_a?(Hash)

      Array(file_coverage[:lines] || file_coverage["lines"])
    end

    def method_counts(file_coverage)
      return {} unless file_coverage.is_a?(Hash)

      file_coverage[:methods] || file_coverage["methods"] || {}
    end
  end
end
