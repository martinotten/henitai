# frozen_string_literal: true

require "open3"

module Henitai
  # Shells out to git to discover changed files between two refs.
  class GitDiffAnalyzer
    def changed_files(from:, to:)
      stdout, stderr, status = Open3.capture3(
        "git",
        "diff",
        "--name-only",
        from,
        to
      )

      raise stderr.strip unless status.success?

      stdout.split("\n").reject(&:empty?)
    end
  end
end
