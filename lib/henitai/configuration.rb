# frozen_string_literal: true

module Henitai
  # Loads and validates .henitai.yml configuration.
  #
  # Configuration is resolved in the following order (last wins):
  #   1. Built-in defaults
  #   2. .henitai.yml in the project root
  #   3. CLI flags
  class Configuration
    DEFAULT_TIMEOUT   = 10.0
    DEFAULT_OPERATORS = :light
    DEFAULT_JOBS      = nil # auto-detect
    DEFAULT_THRESHOLDS = { high: 80, low: 60 }.freeze
    CONFIG_FILE        = ".henitai.yml"

    attr_reader :integration, :includes, :operators, :timeout,
                :ignore_patterns, :jobs, :coverage_criteria,
                :thresholds, :reporters, :dashboard

    # @param path [String] path to .henitai.yml (default: project root)
    def self.load(path: CONFIG_FILE)
      new(path:)
    end

    def initialize(path: CONFIG_FILE)
      raw = File.exist?(path) ? YAML.safe_load_file(path, symbolize_names: true) : {}
      apply_defaults(raw)
    end

    private

    def apply_defaults(raw)
      @integration       = raw.dig(:integration, :name) || "rspec"
      @includes          = raw[:includes] || ["lib"]
      @operators         = (raw.dig(:mutation, :operators) || DEFAULT_OPERATORS).to_sym
      @timeout           = raw.dig(:mutation, :timeout) || DEFAULT_TIMEOUT
      @ignore_patterns   = raw.dig(:mutation, :ignore_patterns) || []
      @jobs              = raw[:jobs]
      @coverage_criteria = raw[:coverage_criteria] || { test_result: true, timeout: false, process_abort: false }
      @thresholds        = raw[:thresholds] || DEFAULT_THRESHOLDS
      @reporters         = raw[:reporters] || ["terminal"]
      @dashboard         = raw[:dashboard] || {}
    end
  end
end
