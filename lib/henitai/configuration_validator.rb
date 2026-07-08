# frozen_string_literal: true

require_relative "configuration_validator/rules"

module Henitai
  # Internal validator for configuration data loaded from YAML and CLI overrides.
  #
  # The public entry point is {.validate!}; the individual rules live in
  # {Rules}. Unknown-key warnings are emitted via {.warn} so that callers (and
  # specs) can observe them on this module.
  module ConfigurationValidator
    VALID_TOP_LEVEL_KEYS = %i[
      integration
      includes
      excludes
      mutation
      coverage_criteria
      thresholds
      reporters
      reports_dir
      all_logs
      dashboard
      jobs
    ].freeze
    VALID_MUTATION_KEYS = %i[operators timeout timeout_multiplier ignore_patterns max_flaky_retries sampling].freeze
    VALID_SAMPLING_KEYS = %i[ratio strategy].freeze
    VALID_COVERAGE_CRITERIA_KEYS = %i[test_result timeout process_abort].freeze
    VALID_THRESHOLDS_KEYS = %i[high low].freeze
    VALID_DASHBOARD_KEYS = %i[project base_url].freeze
    VALID_INTEGRATION_KEYS = %i[name].freeze
    VALID_OPERATORS = %i[light full].freeze
    VALIDATION_STEPS = %i[
      validate_top_level_keys
      validate_integration
      validate_includes
      validate_excludes
      validate_jobs
      validate_reporters
      validate_reports_dir
      validate_all_logs
      validate_dashboard
      validate_mutation
      validate_coverage_criteria
      validate_thresholds
    ].freeze

    def self.validate!(raw)
      Rules.ensure_hash!(raw, "configuration")
      VALIDATION_STEPS.each { |step| Rules.public_send(step, raw) }
    end

    def self.warn(message)
      Kernel.warn(message)
    end
  end
end
