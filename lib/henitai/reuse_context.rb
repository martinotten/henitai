# frozen_string_literal: true

require "digest"
require "json"

require_relative "verdict_fingerprint"

module Henitai
  # Run-level fingerprint of everything outside a mutant and its covering
  # tests that can change a verdict: the test dependency files, the
  # verdict-relevant configuration (including whether control runs verified
  # the detections, ADR-16) and the henitai version. Recorded with every
  # cached Killed/Survived verdict and required to match for reuse.
  #
  # Computed once per instance, so the filter that reads verdicts and the
  # history store that writes them always agree. nil when the dependency files
  # cannot be read — nothing is then reusable.
  class ReuseContext
    def initialize(config:, version: Henitai::VERSION, root: Dir.pwd)
      @config = config
      @version = version
      @root = root
    end

    def fingerprint
      return @fingerprint if defined?(@fingerprint)

      @fingerprint = compute
    end

    private

    def compute
      dependencies = VerdictFingerprint.dependency_fingerprint(@root)
      return nil unless dependencies

      Digest::SHA256.hexdigest(JSON.generate(components(dependencies)))
    end

    def components(dependencies)
      {
        "dependencies" => dependencies,
        "version" => @version,
        "integration" => @config.integration.to_s,
        "operators" => @config.operators.to_s,
        "test_excludes" => Array(@config.test_excludes).map(&:to_s).sort,
        "coverage_criteria" => @config.coverage_criteria.to_h.sort_by { |key, _| key.to_s },
        "control_runs" => @config.control_runs == true
      }
    end
  end
end
