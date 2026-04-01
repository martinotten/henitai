# frozen_string_literal: true

require "open3"
require_relative "subject_resolver"

module Henitai
  class GitDiffError < StandardError; end

  # Shells out to git to discover changed files between two refs.
  #
  # By default the analyzer runs in the current working directory. Callers can
  # pass dir: to point it at another repository root without changing cwd.
  class GitDiffAnalyzer
    def changed_files(from:, to:, dir: Dir.pwd)
      stdout, stderr, status = git_diff(dir, "--name-only", from, to)

      raise GitDiffError, stderr.strip unless status.success?

      stdout.split("\n").reject(&:empty?)
    end

    def changed_methods(from:, to:, dir: Dir.pwd)
      changed_files(from:, to:, dir:).flat_map do |path|
        changed_methods_in_file(path, from:, to:, dir:)
      end
    end

    private

    def changed_methods_in_file(path, from:, to:, dir:)
      subjects = SubjectResolver.new.resolve_from_files([File.expand_path(path, dir)])
      changed_ranges = changed_line_ranges(path, from:, to:, dir:)

      subjects.select do |subject|
        subject.source_range &&
          changed_ranges.any? do |range|
            ranges_overlap?(subject.source_range, range)
          end
      end
    end

    def changed_line_ranges(path, from:, to:, dir:)
      stdout, stderr, status = git_diff(dir, "--unified=0", from, to, "--", path)

      raise GitDiffError, stderr.strip unless status.success?

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

    def git_diff(dir, *git_args)
      command = ["git"]
      command += ["-C", dir] if dir
      command << "diff"
      command.concat(git_args)

      Open3.capture3(*command)
    end
  end
end
