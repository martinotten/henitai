# frozen_string_literal: true

require_relative "../parser_current"
require "unparser"

module Henitai
  class Mutant
    # Builds the parameter-list fragment of a +define_method+ block from a
    # subject's method-definition AST node.
    #
    # Given the +def+/+defs+/+block+ node for a method, {#build} returns the
    # comma-separated parameter source (e.g. "a, b = 1, *rest, key:, &blk")
    # suitable for splicing into a +define_method(:name) do |...| ...+ template.
    class ParameterSource
      SERIALIZER_METHODS = {
        arg: :argument_parameter_fragment,
        optarg: :optional_parameter_fragment,
        restarg: :rest_parameter_fragment,
        kwarg: :keyword_parameter_fragment,
        kwoptarg: :optional_keyword_parameter_fragment,
        kwrestarg: :keyword_rest_parameter_fragment,
        blockarg: :block_parameter_fragment,
        forward_arg: :forward_parameter_fragment
      }.freeze

      def build(subject_node)
        args_node = method_arguments(subject_node)
        return "" unless args_node
        return forward_parameter_fragment(nil) if args_node.type == :forward_args

        args_node.children.filter_map do |argument|
          parameter_fragment(argument)
        end.join(", ")
      end

      private

      def method_arguments(subject_node)
        case subject_node&.type
        when :def, :block
          subject_node.children[1]
        when :defs
          subject_node.children[2]
        end
      end

      def parameter_fragment(argument)
        method_name = SERIALIZER_METHODS[argument&.type]
        return unless method_name

        send(method_name, argument)
      end

      def argument_parameter_fragment(argument)
        argument.children[0].to_s
      end

      def optional_parameter_fragment(argument)
        "#{argument.children[0]} = #{compile_safe_unparse(argument.children[1])}"
      end

      def rest_parameter_fragment(argument)
        prefixed_parameter(argument, "*")
      end

      def keyword_parameter_fragment(argument)
        "#{argument.children[0]}:"
      end

      def optional_keyword_parameter_fragment(argument)
        "#{argument.children[0]}: #{compile_safe_unparse(argument.children[1])}"
      end

      def keyword_rest_parameter_fragment(argument)
        prefixed_parameter(argument, "**")
      end

      def block_parameter_fragment(argument)
        "&#{argument.children[0]}"
      end

      def forward_parameter_fragment(_argument)
        "*args, **kwargs, &block"
      end

      def prefixed_parameter(argument, prefix)
        name = argument.children[0]
        name ? "#{prefix}#{name}" : prefix
      end

      def compile_safe_unparse(node)
        Unparser.unparse(node)
      rescue StandardError => e
        raise Unparser::UnsupportedNodeError, e.message
      end
    end
  end
end
