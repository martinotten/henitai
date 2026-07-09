# frozen_string_literal: true

require_relative "scalars"

module Henitai
  module ConfigurationValidator
    # Section-level validation rules.
    #
    # Each +validate_*+ method inspects one configuration section, warns about
    # unknown keys via {ConfigurationValidator.warn}, and delegates leaf value
    # checks to {Scalars}. Failures raise +Henitai::ConfigurationError+.
    module Rules
      module_function

      def validate_top_level_keys(raw)
        warn_unknown_keys(raw, VALID_TOP_LEVEL_KEYS)
      end

      def validate_integration(raw)
        value = raw[:integration]
        return if value.nil?
        return if value.is_a?(String)

        ensure_hash!(value, "integration")
        warn_unknown_keys(value, VALID_INTEGRATION_KEYS, "integration")
        Scalars.validate_optional_string(value[:name], "integration.name")
      end

      def validate_includes(raw)
        Scalars.validate_string_array(raw[:includes], "includes")
      end

      def validate_excludes(raw)
        Scalars.validate_string_array(raw[:excludes], "excludes")
      end

      def validate_jobs(raw)
        value = raw[:jobs]
        return if value.nil?
        return if value.is_a?(Integer)

        configuration_error("Invalid configuration value for jobs: expected Integer, got #{value.class}")
      end

      def validate_reporters(raw)
        Scalars.validate_string_array(raw[:reporters], "reporters")
      end

      def validate_reports_dir(raw)
        Scalars.validate_optional_string(raw[:reports_dir], "reports_dir")
      end

      def validate_reports(raw)
        value = raw[:reports]
        return if value.nil?

        ensure_hash!(value, "reports")
        warn_unknown_keys(value, VALID_REPORTS_KEYS, "reports")
        Scalars.validate_boolean(value[:checkpoint], "reports.checkpoint") unless value[:checkpoint].nil?
        Scalars.validate_checkpoint_every(value[:checkpoint_every])
        Scalars.validate_checkpoint_interval(value[:checkpoint_interval])
      end

      def validate_all_logs(raw)
        value = raw[:all_logs]
        return if value.nil?

        Scalars.validate_boolean(value, "all_logs")
      end

      def validate_dashboard(raw)
        value = raw[:dashboard]
        return if value.nil?

        ensure_hash!(value, "dashboard")
        warn_unknown_keys(value, VALID_DASHBOARD_KEYS, "dashboard")
        Scalars.validate_optional_string(value[:project], "dashboard.project")
        Scalars.validate_optional_string(value[:base_url], "dashboard.base_url")
      end

      def validate_mutation(raw)
        value = raw[:mutation]
        return if value.nil?

        ensure_hash!(value, "mutation")
        warn_unknown_keys(value, VALID_MUTATION_KEYS, "mutation")
        Scalars.validate_operator(value[:operators])
        validate_mutation_limits(value)
        validate_mutation_filters(value)
        validate_sampling(value[:sampling])
      end

      def validate_mutation_limits(value)
        Scalars.validate_timeout(value[:timeout])
        Scalars.validate_timeout_multiplier(value[:timeout_multiplier])
        Scalars.validate_max_flaky_retries(value[:max_flaky_retries])
        Scalars.validate_max_log_bytes(value[:max_log_bytes])
        Scalars.validate_max_timeout(value[:max_timeout])
      end

      def validate_mutation_filters(value)
        Scalars.validate_string_array(value[:ignore_patterns], "mutation.ignore_patterns")
        Scalars.validate_ignore_patterns(value[:ignore_patterns])
      end

      def validate_coverage_criteria(raw)
        value = raw[:coverage_criteria]
        return if value.nil?

        ensure_hash!(value, "coverage_criteria")
        warn_unknown_keys(value, VALID_COVERAGE_CRITERIA_KEYS, "coverage_criteria")
        value.each { |key, flag| Scalars.validate_boolean(flag, "coverage_criteria.#{key}") }
      end

      def validate_thresholds(raw)
        value = raw[:thresholds]
        return if value.nil?

        ensure_hash!(value, "thresholds")
        warn_unknown_keys(value, VALID_THRESHOLDS_KEYS, "thresholds")
        value.each { |key, threshold| Scalars.validate_threshold(threshold, "thresholds.#{key}") }
      end

      def validate_sampling(value)
        return if value.nil?

        ensure_hash!(value, "mutation.sampling")
        warn_unknown_keys(value, VALID_SAMPLING_KEYS, "mutation.sampling")
        Scalars.validate_sampling_completeness(value)
        Scalars.validate_sampling_ratio(value[:ratio])
        Scalars.validate_sampling_strategy(value[:strategy])
      end

      def warn_unknown_keys(raw, allowed_keys, path = nil)
        raw.each_key do |key|
          next if allowed_keys.include?(key)

          ConfigurationValidator.warn "Unknown configuration key: #{key_path(path, key)}"
        end
      end

      def key_path(path, key)
        path ? "#{path}.#{key}" : key.to_s
      end

      def ensure_hash!(value, path)
        return if value.is_a?(Hash)

        configuration_error("Invalid configuration value for #{path}: expected Hash, got #{value.class}")
      end

      def configuration_error(message)
        raise Henitai::ConfigurationError, message
      end
    end
  end
end
