# frozen_string_literal: true

require "prism"

module Henitai
  # Reads `# henitai:disable` magic comments from subject source files and
  # decides whether a mutant is excluded from the run.
  #
  # Two forms are supported:
  #   - trailing comment on a code line: skips mutants starting on that line
  #   - standalone comment in the contiguous comment block directly above a
  #     `def`: skips every mutant of that subject
  #
  # Matching mutants are reported as ignored by {StaticFilter}, not dropped.
  class MutationSkipDirectives
    DIRECTIVE = /#\s*henitai:disable\b/

    # Per-file directive line numbers, classified by comment position.
    Index = Data.define(:trailing_directive_lines, :standalone_directive_lines, :standalone_comment_lines)
    EMPTY_INDEX = Index.new(
      trailing_directive_lines: Set.new.freeze,
      standalone_directive_lines: Set.new.freeze,
      standalone_comment_lines: Set.new.freeze
    ).freeze

    def initialize
      @index_cache = {}
    end

    def skip?(mutant)
      line_skipped?(mutant) || method_skipped?(mutant)
    end

    private

    def line_skipped?(mutant)
      index_for(mutant.location[:file]).trailing_directive_lines.include?(mutant.location[:start_line])
    end

    def method_skipped?(mutant)
      range = mutant.subject&.source_range
      return false unless range

      index = index_for(mutant.subject.source_file)
      line = range.begin - 1
      while index.standalone_comment_lines.include?(line)
        return true if index.standalone_directive_lines.include?(line)

        line -= 1
      end
      false
    end

    def index_for(path)
      mtime = File.mtime(path)
      cached_mtime, cached_index = @index_cache[path]
      return cached_index if cached_mtime == mtime

      index = build_index(path)
      @index_cache[path] = [mtime, index]
      index
    rescue Errno::ENOENT, Errno::EACCES
      EMPTY_INDEX
    end

    def build_index(path)
      source = File.read(path)
      lines = source.lines
      buckets = { trailing: Set.new, standalone_directive: Set.new, standalone_comment: Set.new }

      Prism.parse(source).comments.each { |comment| record_comment(comment, lines, buckets) }

      Index.new(
        trailing_directive_lines: buckets[:trailing].freeze,
        standalone_directive_lines: buckets[:standalone_directive].freeze,
        standalone_comment_lines: buckets[:standalone_comment].freeze
      )
    end

    def record_comment(comment, lines, buckets)
      line = comment.location.start_line
      standalone = standalone?(comment, lines)
      buckets[:standalone_comment] << line if standalone
      return unless DIRECTIVE.match?(comment.slice)

      (standalone ? buckets[:standalone_directive] : buckets[:trailing]) << line
    end

    def standalone?(comment, lines)
      prefix = lines[comment.location.start_line - 1].to_s[0...comment.location.start_column]
      prefix.strip.empty?
    end
  end
end
