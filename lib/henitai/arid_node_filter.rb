# frozen_string_literal: true

module Henitai
  # Suppresses AST nodes that are unlikely to produce useful mutants.
  class AridNodeFilter
    DIRECT_OUTPUT_METHODS = %i[puts p pp warn].freeze
    DIRECT_DEBUG_METHODS = %i[byebug debugger].freeze
    BINDING_DEBUG_METHODS = %i[pry].freeze
    LOGGER_METHODS = %i[debug info warn error fatal].freeze
    INVARIANT_METHODS = %i[is_a? respond_to? kind_of?].freeze
    DSL_METHODS = %i[let subject before after].freeze

    def suppressed?(node, config)
      custom_pattern_match?(node, config) || catalog_match?(node)
    end

    private

    def custom_pattern_match?(node, config)
      source = node.location&.expression&.source
      return false unless source

      Array(config&.ignore_patterns).any? do |pattern|
        Regexp.new(pattern).match?(source)
      end
    end

    def catalog_match?(node)
      case node.type
      when :send
        send_match?(node)
      when :block
        block_match?(node)
      when :or_asgn
        true
      else
        false
      end
    end

    def send_match?(node)
      receiver, method_name, = node.children
      method_name = method_name&.to_sym

      return true if direct_output_call?(receiver, method_name)
      return true if direct_debug_call?(receiver, method_name)
      return true if binding_debug_call?(receiver, method_name)
      return true if rails_logger_call?(receiver, method_name)

      invariant_call?(method_name)
    end

    def block_match?(node)
      send_node = node.children.first
      return false unless send_node&.type == :send

      receiver, method_name, = send_node.children
      receiver.nil? && DSL_METHODS.include?(method_name.to_sym)
    end

    def direct_output_call?(receiver, method_name)
      receiver.nil? && DIRECT_OUTPUT_METHODS.include?(method_name)
    end

    def direct_debug_call?(receiver, method_name)
      receiver.nil? && DIRECT_DEBUG_METHODS.include?(method_name)
    end

    def binding_debug_call?(receiver, method_name)
      send_call?(receiver, :binding) && BINDING_DEBUG_METHODS.include?(method_name)
    end

    def rails_logger_call?(receiver, method_name)
      logger_receiver?(receiver) && LOGGER_METHODS.include?(method_name)
    end

    def invariant_call?(method_name)
      INVARIANT_METHODS.include?(method_name)
    end

    def logger_receiver?(node)
      send_call?(node, :logger) &&
        node.children.first&.type == :const &&
        node.children.first.children.last == :Rails
    end

    def send_call?(node, method_name)
      node&.type == :send && node.children[1] == method_name
    end
  end
end
