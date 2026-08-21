# frozen_string_literal: true

module Henitai
  # Turns a list of source files into the subjects a run mutates, applying any
  # CLI subject patterns.
  #
  # With no patterns every resolved subject is kept. With patterns, each is
  # applied independently and the results concatenated, so overlapping patterns
  # can name the same subject twice — hence the de-duplication on
  # `[expression, source_file]` rather than on object identity. Expression alone
  # is not enough: the same expression can legitimately appear in two files.
  class SubjectSelection
    def initialize(subject_resolver:, patterns:)
      @subject_resolver = subject_resolver
      @patterns = patterns
    end

    def resolve(source_files)
      subjects = @subject_resolver.resolve_from_files(source_files)
      return subjects if pattern_expressions.empty?

      unique(pattern_expressions.flat_map { |expression| @subject_resolver.apply_pattern(subjects, expression) })
    end

    def unique(subjects)
      subjects.uniq { |subject| [subject.expression, subject.source_file] }
    end

    private

    def pattern_expressions = Array(@patterns).map(&:expression)
  end
end
