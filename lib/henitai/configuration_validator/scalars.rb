# frozen_string_literal: true

module Henitai
  module ConfigurationValidator
    # Leaf validators for individual configuration values.
    #
    # Each method returns silently for an acceptable value or raises
    # +Henitai::ConfigurationError+ via {Rules.configuration_error}.
    module Scalars
      module_function

      def validate_operator(value)
        return if value.nil?

        operator = value.respond_to?(:to_sym) ? value.to_sym : nil
        return if VALID_OPERATORS.include?(operator)

        Rules.configuration_error(
          "Invalid configuration value for mutation.operators: expected one of " \
          "#{VALID_OPERATORS.join(', ')}, got #{value.inspect}"
        )
      end

      def validate_timeout(value)
        return if value.nil?
        return if value.is_a?(Numeric)

        Rules.configuration_error(
          "Invalid configuration value for mutation.timeout: expected Numeric, got #{value.class}"
        )
      end

      def validate_timeout_multiplier(value)
        return if value.nil?
        return if value.is_a?(Numeric) && value.positive?

        Rules.configuration_error(
          "Invalid configuration value for mutation.timeout_multiplier: " \
          "expected positive Numeric, got #{value.inspect}"
        )
      end

      def validate_threshold(value, path)
        return if value.is_a?(Integer) && value.between?(0, 100)

        Rules.configuration_error(
          "Invalid configuration value for #{path}: expected Integer between 0 and 100, " \
          "got #{value.inspect}"
        )
      end

      def validate_boolean(value, path)
        return if [true, false].include?(value)

        Rules.configuration_error(
          "Invalid configuration value for #{path}: expected true or false, got #{value.inspect}"
        )
      end

      def validate_optional_string(value, path)
        return if value.nil?
        return if value.is_a?(String)

        Rules.configuration_error("Invalid configuration value for #{path}: expected String, got #{value.class}")
      end

      def validate_string_array(value, path)
        return if value.nil?
        return if value.is_a?(Array) && value.all?(String)

        Rules.configuration_error(
          "Invalid configuration value for #{path}: expected Array<String>, got #{describe_array_type(value)}"
        )
      end

      def validate_ignore_patterns(value)
        Array(value).each do |pattern|
          Regexp.new(pattern)
        rescue RegexpError => e
          Rules.configuration_error(
            "Invalid configuration value for mutation.ignore_patterns: " \
            "invalid regular expression #{pattern.inspect}: #{e.message}"
          )
        end
      end

      def validate_max_flaky_retries(value)
        return if value.nil?
        return if value.is_a?(Integer) && value >= 0

        Rules.configuration_error(
          "Invalid configuration value for mutation.max_flaky_retries: expected Integer >= 0, got #{value.inspect}"
        )
      end

      def validate_sampling_ratio(value)
        return if value.nil?
        return if value.is_a?(Numeric) && value >= 0.0 && value <= 1.0

        Rules.configuration_error(
          "Invalid configuration value for mutation.sampling.ratio: " \
          "expected Numeric between 0 and 1, got #{value.inspect}"
        )
      end

      def validate_sampling_strategy(value)
        return if value.nil?

        strategy = value.respond_to?(:to_sym) ? value.to_sym : nil
        return if strategy == :stratified

        Rules.configuration_error(
          "Invalid configuration value for mutation.sampling.strategy: expected stratified, got #{value.inspect}"
        )
      end

      def validate_sampling_completeness(value)
        return if value.key?(:ratio) && value.key?(:strategy)

        Rules.configuration_error(
          "Invalid configuration value for mutation.sampling: expected both ratio and strategy"
        )
      end

      def describe_array_type(value)
        return value.class.name unless value.is_a?(Array)

        element_types = value.map { |item| item.class.name }.uniq.join(", ")
        "Array<#{element_types}>"
      end
    end
  end
end
