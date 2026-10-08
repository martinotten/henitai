# frozen_string_literal: true

require "open3"
require_relative "subject_resolver"

module Henitai
  class GitDiffError < StandardError; end

  # Shells out to git to discover changed files between two refs.
  #
  # By default the analyzer runs in the current working directory. Callers can
  # pass dir: to point it at another directory without changing cwd.
  #
  # Every path is reported relative to that directory, which need not be the
  # repository root: `git diff` would otherwise print root-relative paths
  # while `git ls-files` prints directory-relative ones. Paths are read
  # NUL-separated so git never quotes non-ASCII names.
  class GitDiffAnalyzer
    NAME_ONLY = ["--name-only", "--relative", "-z"].freeze

    def changed_files(from:, to:, dir: Dir.pwd)
      stdout, stderr, status = git_diff(dir, *NAME_ONLY, from, to)

      raise GitDiffError, stderr.strip unless status.success?

      paths(stdout)
    end

    def working_tree_changed_files(dir: Dir.pwd)
      tracked = working_tree_tracked_files(dir)
      untracked = untracked_files(dir)

      (tracked + untracked).uniq
    end

    def head_sha(dir: Dir.pwd)
      command = ["git", "-C", dir, "rev-parse", "HEAD"]
      stdout, _, status = Open3.capture3(*command)
      stdout.strip if status.success? && !stdout.strip.empty?
    rescue Errno::ENOENT
      nil
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
      stdout, stderr, status = git_diff(dir, "--unified=0", "--relative", from, to, "--", path)

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

    def working_tree_tracked_files(dir)
      stdout, stderr, status = git_diff(dir, *NAME_ONLY, "HEAD")

      raise GitDiffError, stderr.strip unless status.success?

      paths(stdout)
    end

    def untracked_files(dir)
      command = ["git"]
      command += ["-C", dir] if dir
      command += ["ls-files", "--others", "--exclude-standard", "-z"]
      stdout, stderr, status = Open3.capture3(*command)

      raise GitDiffError, stderr.strip unless status.success?

      paths(stdout)
    end

    def paths(stdout)
      stdout.dup.force_encoding(Encoding::UTF_8).split("\0").reject(&:empty?)
    end
  end
end
