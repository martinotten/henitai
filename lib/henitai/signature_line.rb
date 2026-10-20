# frozen_string_literal: true

module Henitai
  # Whether a mutant sits on its subject's def (signature) line. Line coverage
  # credits that line only to the test that loaded the file, so the tests that
  # exercise it are not knowable from the per-test map alone.
  module SignatureLine
    module_function

    # A subject without a source range (a recipe stub) has an unknown def
    # line, so it is treated as one: that only widens test selection and
    # blocks verdict reuse.
    def on?(mutant)
      subject = mutant.respond_to?(:subject) ? mutant.subject : nil
      return false unless subject.respond_to?(:source_range)

      range = subject.source_range
      range.nil? || range.begin == mutant.location[:start_line]
    end
  end
end
