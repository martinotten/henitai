# frozen_string_literal: true

module Henitai
  class CLI
    # Shared helpers for CLI command handlers: configuration loading (applying
    # CLI overrides on top of the config file) and uniform error handling.
    module CommandSupport
      private

      def load_config(options)
        Configuration.load(
          path: options.fetch(:config, Configuration::CONFIG_FILE),
          overrides: configuration_overrides(options)
        )
      end

      def configuration_overrides(options)
        deep_compact(
          {
            integration: options[:integration],
            all_logs: options[:all_logs],
            mutation: {
              operators: options[:operators],
              timeout: options[:timeout]
            },
            jobs: options[:jobs]
          }
        )
      end

      def deep_compact(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested_value), result|
            compacted = deep_compact(nested_value)
            result[key] = compacted unless compacted.nil?
          end
        when Array
          value.map { |item| deep_compact(item) }.compact
        else
          value
        end
      end

      def handle_run_error(error)
        warn "#{error.class}: #{error.message}"
        exit 2
      end
    end
  end
end
