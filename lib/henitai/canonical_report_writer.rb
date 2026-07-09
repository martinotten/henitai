# frozen_string_literal: true

require "fileutils"
require "json"

module Henitai
  # Writes a Stryker schema to the canonical report path.
  #
  # Authoritative (full-run) writes replace the file wholesale; non-authoritative
  # writes (scoped/partial runs, and every incremental checkpoint after the
  # first) merge into the existing report via {CanonicalReportMerger}, pruning
  # entries whose source file no longer exists. Shared by the JSON reporter and
  # the {CheckpointReporter} so both persist the report identically.
  module CanonicalReportWriter
    def self.write(schema, path:, authoritative:)
      output = authoritative ? schema : CanonicalReportMerger.merge(schema, path, prune_missing: true)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(output))
    end
  end
end
