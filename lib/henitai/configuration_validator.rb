# frozen_string_literal: true

module Henitai
  # rubocop:disable Metrics/ModuleLength
  # Internal validator for configuration data loaded from YAML and CLI overrides.
  module ConfigurationValidator
    VALID_TOP_LEVEL_KEYS = %i[
      integration
      includes
      mutation
      coverage_criteria
      thresholds
      reporters
      reports_dir
      dashboard
      jobs
    ].freeze
    VALID_MUTATION_KEYS = %i[operators timeout ignore_patterns max_mutants_per_line max_flaky_retries sampling].freeze
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
      validate_jobs
      validate_reporters
      validate_reports_dir
      validate_dashboard
      validate_mutation
      validate_coverage_criteria
      validate_thresholds
    ].freeze

    def self.validate!(raw)
      ensure_hash!(raw, "configuration")
      VALIDATION_STEPS.each { |step| send(step, raw) }
    end

    class << self
      private

      def validate_top_level_keys(raw)
        warn_unknown_keys(raw, VALID_TOP_LEVEL_KEYS)
      end

      def validate_integration(raw)
        value = raw[:integration]
        return if value.nil?
        return if value.is_a?(String)

        ensure_hash!(value, "integration")
        warn_unknown_keys(value, VALID_INTEGRATION_KEYS, "integration")
        validate_optional_string(value[:name], "integration.name")
      end

      def validate_includes(raw)
        validate_string_array(raw[:includes], "includes")
      end

      def validate_jobs(raw)
        value = raw[:jobs]
        return if value.nil?
        return if value.is_a?(Integer)

        configuration_error("Invalid configuration value for jobs: expected Integer, got #{value.class}")
      end

      def validate_reporters(raw)
        validate_string_array(raw[:reporters], "reporters")
      end

      def validate_reports_dir(raw)
        validate_optional_string(raw[:reports_dir], "reports_dir")
      end

      def validate_dashboard(raw)
        value = raw[:dashboard]
        return if value.nil?

        ensure_hash!(value, "dashboard")
        warn_unknown_keys(value, VALID_DASHBOARD_KEYS, "dashboard")
        validate_optional_string(value[:project], "dashboard.project")
        validate_optional_string(value[:base_url], "dashboard.base_url")
      end

      def validate_mutation(raw)
        value = raw[:mutation]
        return if value.nil?

        ensure_hash!(value, "mutation")
        warn_unknown_keys(value, VALID_MUTATION_KEYS, "mutation")
        validate_operator(value[:operators])
        validate_mutation_limits(value)
        validate_mutation_filters(value)
        validate_sampling(value[:sampling])
      end

      def validate_mutation_limits(value)
        validate_timeout(value[:timeout])
        validate_max_mutants_per_line(value[:max_mutants_per_line])
        validate_max_flaky_retries(value[:max_flaky_retries])
      end

      def validate_mutation_filters(value)
        validate_string_array(value[:ignore_patterns], "mutation.ignore_patterns")
        validate_ignore_patterns(value[:ignore_patterns])
      end

      def validate_coverage_criteria(raw)
        value = raw[:coverage_criteria]
        return if value.nil?

        ensure_hash!(value, "coverage_criteria")
        warn_unknown_keys(value, VALID_COVERAGE_CRITERIA_KEYS, "coverage_criteria")
        value.each do |key, flag|
          validate_boolean(flag, "coverage_criteria.#{key}")
        end
      end

      def validate_thresholds(raw)
        value = raw[:thresholds]
        return if value.nil?

        ensure_hash!(value, "thresholds")
        warn_unknown_keys(value, VALID_THRESHOLDS_KEYS, "thresholds")
        value.each do |key, threshold|
          validate_threshold(threshold, "thresholds.#{key}")
        end
      end

      def validate_operator(value)
        return if value.nil?

        operator = value.respond_to?(:to_sym) ? value.to_sym : nil
        return if VALID_OPERATORS.include?(operator)

        configuration_error(
          "Invalid configuration value for mutation.operators: expected one of " \
          "#{VALID_OPERATORS.join(', ')}, got #{value.inspect}"
        )
      end

      def validate_timeout(value)
        return if value.nil?
        return if value.is_a?(Numeric)

        configuration_error("Invalid configuration value for mutation.timeout: expected Numeric, got #{value.class}")
      end

      def validate_threshold(value, path)
        return if value.is_a?(Integer) && value.between?(0, 100)

        configuration_error(
          "Invalid configuration value for #{path}: expected Integer between 0 and 100, " \
          "got #{value.inspect}"
        )
      end

      def validate_boolean(value, path)
        return if [true, false].include?(value)

        configuration_error("Invalid configuration value for #{path}: expected true or false, got #{value.inspect}")
      end

      def validate_optional_string(value, path)
        return if value.nil?
        return if value.is_a?(String)

        configuration_error("Invalid configuration value for #{path}: expected String, got #{value.class}")
      end

      def validate_string_array(value, path)
        return if value.nil?
        return if value.is_a?(Array) && value.all?(String)

        configuration_error(
          "Invalid configuration value for #{path}: expected Array<String>, got #{describe_array_type(value)}"
        )
      end

      def validate_ignore_patterns(value)
        Array(value).each do |pattern|
          Regexp.new(pattern)
        rescue RegexpError => e
          configuration_error(
            "Invalid configuration value for mutation.ignore_patterns: " \
            "invalid regular expression #{pattern.inspect}: #{e.message}"
          )
        end
      end

      def validate_max_mutants_per_line(value)
        return if value.nil?
        return if value.is_a?(Integer) && value >= 1

        configuration_error(
          "Invalid configuration value for mutation.max_mutants_per_line: expected Integer >= 1, got #{value.inspect}"
        )
      end

      def validate_max_flaky_retries(value)
        return if value.nil?
        return if value.is_a?(Integer) && value >= 0

        configuration_error(
          "Invalid configuration value for mutation.max_flaky_retries: expected Integer >= 0, got #{value.inspect}"
        )
      end

      def validate_sampling(value)
        return if value.nil?

        ensure_hash!(value, "mutation.sampling")
        warn_unknown_keys(value, VALID_SAMPLING_KEYS, "mutation.sampling")
        validate_sampling_completeness(value)
        validate_sampling_ratio(value[:ratio])
        validate_sampling_strategy(value[:strategy])
      end

      def validate_sampling_ratio(value)
        return if value.nil?
        return if value.is_a?(Numeric) && value >= 0.0 && value <= 1.0

        configuration_error(
          "Invalid configuration value for mutation.sampling.ratio: " \
          "expected Numeric between 0 and 1, got #{value.inspect}"
        )
      end

      def validate_sampling_strategy(value)
        return if value.nil?

        strategy = value.respond_to?(:to_sym) ? value.to_sym : nil
        return if strategy == :stratified

        configuration_error(
          "Invalid configuration value for mutation.sampling.strategy: expected stratified, got #{value.inspect}"
        )
      end

      def validate_sampling_completeness(value)
        return if value.key?(:ratio) && value.key?(:strategy)

        configuration_error(
          "Invalid configuration value for mutation.sampling: expected both ratio and strategy"
        )
      end

      def warn_unknown_keys(raw, allowed_keys, path = nil)
        raw.each_key do |key|
          next if allowed_keys.include?(key)

          warn "Unknown configuration key: #{key_path(path, key)}"
        end
      end

      def key_path(path, key)
        path ? "#{path}.#{key}" : key.to_s
      end

      def ensure_hash!(value, path)
        return if value.is_a?(Hash)

        configuration_error("Invalid configuration value for #{path}: expected Hash, got #{value.class}")
      end

      def describe_array_type(value)
        return value.class.name unless value.is_a?(Array)

        element_types = value.map { |item| item.class.name }.uniq.join(", ")
        "Array<#{element_types}>"
      end

      def configuration_error(message)
        raise Henitai::ConfigurationError, message
      end
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
