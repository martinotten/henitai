# frozen_string_literal: true

require "psych"

require_relative "configuration_validator"

module Henitai
  # Loads and validates .henitai.yml configuration.
  #
  # Configuration is resolved from built-in defaults and the project-root
  # `.henitai.yml` file.
  class Configuration
    DEFAULT_TIMEOUT   = 10.0
    DEFAULT_OPERATORS = :light
    DEFAULT_JOBS      = nil # auto-detect
    DEFAULT_MAX_MUTANTS_PER_LINE = 1
    DEFAULT_REPORTS_DIR = "reports"
    DEFAULT_COVERAGE_CRITERIA = {
      test_result: true,
      timeout: false,
      process_abort: false
    }.freeze
    DEFAULT_THRESHOLDS = { high: 80, low: 60 }.freeze
    CONFIG_FILE        = ".henitai.yml"

    attr_reader :integration, :includes, :operators, :timeout,
                :ignore_patterns, :max_mutants_per_line, :sampling, :jobs,
                :coverage_criteria, :thresholds, :reporters, :reports_dir,
                :dashboard

    # @param path [String] path to .henitai.yml (default: project root)
    def self.load(path: CONFIG_FILE, overrides: {})
      new(path:, overrides:)
    end

    def initialize(path: CONFIG_FILE, overrides: {})
      raw = load_raw_configuration(path)
      unless raw.is_a?(Hash)
        raise Henitai::ConfigurationError,
              "Invalid configuration value for configuration: expected Hash, got #{raw.class}"
      end
      merged = merge_defaults(raw, symbolize_keys(overrides))
      ConfigurationValidator.validate!(merged)
      apply_defaults(merged)
    end

    private

    def load_raw_configuration(path)
      return {} unless File.exist?(path)

      raw = Psych.safe_load(File.read(path), symbolize_names: true)
      raw || {}
    end

    def apply_defaults(raw)
      apply_general_defaults(raw)
      apply_mutation_defaults(raw)
      apply_analysis_defaults(raw)
    end

    def apply_general_defaults(raw)
      integration = raw[:integration]
      @integration = if integration.is_a?(Hash)
                       integration[:name] || "rspec"
                     elsif integration.nil?
                       "rspec"
                     else
                       integration
                     end
      @includes = raw[:includes] || ["lib"]
      @jobs = raw[:jobs]
      @reporters = raw[:reporters] || ["terminal"]
      @reports_dir = raw[:reports_dir] || DEFAULT_REPORTS_DIR
      # @type var empty_dashboard: Hash[Symbol, untyped]
      empty_dashboard = {}
      @dashboard = merge_defaults(empty_dashboard, raw[:dashboard])
    end

    def apply_mutation_defaults(raw)
      mutation = raw[:mutation] || {}

      @operators = (mutation[:operators] || DEFAULT_OPERATORS).to_sym
      @timeout = mutation[:timeout] || DEFAULT_TIMEOUT
      @ignore_patterns = mutation[:ignore_patterns] || []
      @max_mutants_per_line = mutation[:max_mutants_per_line] || DEFAULT_MAX_MUTANTS_PER_LINE
      @sampling = mutation[:sampling]
    end

    def apply_analysis_defaults(raw)
      @coverage_criteria = merge_defaults(DEFAULT_COVERAGE_CRITERIA,
                                          raw[:coverage_criteria])
      @thresholds = merge_defaults(DEFAULT_THRESHOLDS, raw[:thresholds])
    end

    def merge_defaults(defaults, overrides)
      return defaults.dup if overrides.nil?

      defaults.merge(overrides) do |_key, default_value, override_value|
        if default_value.is_a?(Hash) && override_value.is_a?(Hash)
          merge_defaults(default_value, override_value)
        else
          override_value
        end
      end
    end

    def symbolize_keys(value)
      case value
      when Hash
        # @type var result: Hash[Symbol, untyped]
        result = {}
        value.each do |key, val|
          result[key.to_sym] = symbolize_keys(val)
        end
        result
      when Array
        value.map { |item| symbolize_keys(item) }
      else
        value
      end
    end
  end
end
