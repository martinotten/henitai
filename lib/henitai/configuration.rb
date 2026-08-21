# frozen_string_literal: true

require "psych"

require_relative "configuration_validator"

module Henitai
  # Loads and validates .henitai.yml configuration.
  #
  # Configuration is resolved from built-in defaults and the project-root
  # `.henitai.yml` file.
  class Configuration
    DEFAULT_TIMEOUT = 10.0
    DEFAULT_TIMEOUT_MULTIPLIER = 3.0
    DEFAULT_OPERATORS = :light
    DEFAULT_JOBS      = 1
    DEFAULT_MAX_FLAKY_RETRIES = 3
    # Cap on captured child stdout/stderr per stream (bytes). A runaway mutant
    # (e.g. one that puts henitai's own suite into a spewing recursion) can
    # otherwise write hundreds of MB per child; overflow is discarded.
    DEFAULT_MAX_LOG_BYTES = 5_000_000
    # Ceiling for the per-mutant auto-calibrated timeout (seconds). Keeps a
    # runaway from running for minutes when the calibrated value is large.
    DEFAULT_MAX_TIMEOUT = 30.0
    # Incremental report checkpoint cadence for long full runs.
    DEFAULT_CHECKPOINT_EVERY = 200
    DEFAULT_CHECKPOINT_INTERVAL = 30.0
    DEFAULT_REPORTS_DIR = "reports"
    # All three default to true because Result's MS numerator has always counted
    # killed + timeout + runtime_error unconditionally. Until 0.5.0 this block
    # was validated but never read, so the shipped `false` defaults described
    # behavior the scorer did not have. Wiring it up with those defaults intact
    # would have silently dropped timeouts and aborts out of every user's score;
    # flipping them keeps the numerator exactly as it was and makes the knob
    # mean what it says. See Result::CRITERION_STATUSES for the mapping.
    DEFAULT_COVERAGE_CRITERIA = {
      test_result: true,
      timeout: true,
      process_abort: true
    }.freeze
    DEFAULT_THRESHOLDS = { high: 80, low: 60 }.freeze
    CONFIG_FILE        = ".henitai.yml"

    attr_reader :integration, :includes, :excludes, :test_excludes, :operators, :timeout,
                :timeout_multiplier, :ignore_patterns, :sampling, :jobs,
                :max_flaky_retries, :max_log_bytes, :max_timeout,
                :coverage_criteria, :thresholds,
                :reporters, :reports_dir,
                :checkpoint_enabled, :checkpoint_every, :checkpoint_interval,
                :dashboard, :all_logs

    # True when mutation.timeout was set explicitly (file or CLI override);
    # a fixed timeout disables per-mutant auto-calibration.
    def timeout_configured?
      @timeout_configured
    end

    # @param path [String] path to .henitai.yml (default: project root)
    def self.load(path: CONFIG_FILE, overrides: {})
      new(path:, overrides:)
    end

    def initialize(path: CONFIG_FILE, overrides: {})
      @config_dir = File.dirname(File.expand_path(path))
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

    def detect_integration
      return "rspec"    if File.exist?(File.join(@config_dir, ".rspec"))
      return "minitest" if File.directory?(File.join(@config_dir, "test"))
      return "rspec"    if File.directory?(File.join(@config_dir, "spec"))

      "rspec"
    end

    def apply_defaults(raw)
      apply_general_defaults(raw)
      apply_mutation_defaults(raw)
      apply_reports_defaults(raw)
      apply_analysis_defaults(raw)
    end

    def apply_general_defaults(raw)
      @integration = resolve_integration_default(raw[:integration])
      @includes = raw[:includes] || ["lib"]
      @excludes = raw[:excludes] || []
      @test_excludes = raw[:test_excludes] || []
      @jobs = raw.fetch(:jobs, DEFAULT_JOBS)
      @reporters = raw[:reporters] || ["terminal"]
      @reports_dir = raw[:reports_dir] || DEFAULT_REPORTS_DIR
      @all_logs = raw[:all_logs] == true
      @dashboard = default_dashboard(raw[:dashboard])
    end

    def apply_mutation_defaults(raw)
      mutation = raw[:mutation] || {}

      @operators = (mutation[:operators] || DEFAULT_OPERATORS).to_sym
      @timeout_configured = !mutation[:timeout].nil?
      @timeout = mutation[:timeout] || DEFAULT_TIMEOUT
      @timeout_multiplier = mutation[:timeout_multiplier] || DEFAULT_TIMEOUT_MULTIPLIER
      @ignore_patterns = mutation[:ignore_patterns] || []
      @sampling = mutation[:sampling]
      apply_mutation_limit_defaults(mutation)
    end

    def apply_mutation_limit_defaults(mutation)
      @max_flaky_retries = mutation.fetch(:max_flaky_retries, DEFAULT_MAX_FLAKY_RETRIES)
      @max_log_bytes = mutation[:max_log_bytes] || DEFAULT_MAX_LOG_BYTES
      @max_timeout = mutation[:max_timeout] || DEFAULT_MAX_TIMEOUT
    end

    def apply_reports_defaults(raw)
      reports = raw[:reports] || {}
      @checkpoint_enabled = reports.fetch(:checkpoint, true)
      @checkpoint_every = reports[:checkpoint_every] || DEFAULT_CHECKPOINT_EVERY
      @checkpoint_interval = reports[:checkpoint_interval] || DEFAULT_CHECKPOINT_INTERVAL
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

    def resolve_integration_default(integration)
      return integration[:name] || detect_integration if integration.is_a?(Hash)
      return detect_integration if integration.nil?

      integration
    end

    def default_dashboard(overrides)
      # @type var empty_dashboard: Hash[Symbol, untyped]
      empty_dashboard = {}
      merge_defaults(empty_dashboard, overrides)
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
