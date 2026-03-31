# frozen_string_literal: true

require "open3"
require_relative "subject_resolver"

module Henitai
  # Shells out to git to discover changed files between two refs.
  class GitDiffAnalyzer
    def changed_files(from:, to:)
      stdout, stderr, status = git_diff("--name-only", from, to)

      raise stderr.strip unless status.success?

      stdout.split("\n").reject(&:empty?)
    end

    def changed_methods(from:, to:)
      changed_files(from:, to:).flat_map do |path|
        changed_methods_in_file(path, from:, to:)
      end
    end

    private

    def changed_methods_in_file(path, from:, to:)
      subjects = SubjectResolver.new.resolve_from_files([path])
      changed_ranges = changed_line_ranges(path, from:, to:)

      subjects.select do |subject|
        subject.source_range &&
          changed_ranges.any? do |range|
            ranges_overlap?(subject.source_range, range)
          end
      end
    end

    def changed_line_ranges(path, from:, to:)
      stdout, stderr, status = git_diff("--unified=0", from, to, "--", path)

      raise stderr.strip unless status.success?

      stdout.each_line.filter_map { |line| changed_range_from_hunk(line) }
    end

    def changed_range_from_hunk(line)
      match = line.match(/\A@@ -\d+(?:,\d+)? \+(?<start>\d+)(?:,(?<count>\d+))? @@/)
      return unless match

      start_line = match[:start].to_i
      line_count = hunk_line_count(match)

      start_line..(start_line + line_count - 1)
    end

    def hunk_line_count(match)
      line_count = match[:count].nil? ? 1 : match[:count].to_i
      # Git uses `+start` for a one-line hunk and `+start,0` for a pure
      # deletion. We still anchor both at the reported start line so the
      # current subject range can absorb the change point.
      line_count = 1 if line_count.zero?
      line_count
    end

    def ranges_overlap?(left, right)
      left.begin <= right.end && right.begin <= left.end
    end

    def git_diff(...)
      Open3.capture3("git", "diff", ...)
    end
  end
end
