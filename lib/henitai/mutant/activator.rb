# frozen_string_literal: true

require "parser/current"
require "unparser"

module Henitai
  class Mutant
    # Activates a mutant inside the forked child process.
    class Activator
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

      def self.activate!(mutant)
        new.activate!(mutant)
      end

      def activate!(mutant)
        subject = mutant.subject
        raise ArgumentError, "Cannot activate wildcard subjects" if subject.method_name.nil?

        target_for(subject).class_eval(method_source(mutant), __FILE__, __LINE__ + 1)
      end

      private

      def target_for(subject)
        target = load_target(subject)
        subject.method_type == :class ? target.singleton_class : target
      end

      def method_source(mutant)
        method_name = mutant.subject.method_name
        parameters = parameter_source(mutant)
        replacement = body_source(mutant)

        <<~RUBY
          define_method(:#{method_name}) do |#{parameters}|
            #{replacement}
          end
        RUBY
      end

      def body_source(mutant)
        subject_node = mutant.subject.ast_node
        return Unparser.unparse(mutant.mutated_node) unless subject_node

        mutated_subject = replace_node(
          subject_node,
          mutant.original_node,
          mutant.mutated_node
        )
        body = method_body(mutated_subject) || Parser::AST::Node.new(:nil, [])
        Unparser.unparse(body)
      end

      def replace_node(node, original_node, mutated_node)
        return mutated_node if same_node?(node, original_node)
        return node unless node.is_a?(Parser::AST::Node)

        updated_children = node.children.map do |child|
          replace_child(child, original_node, mutated_node)
        end

        return node if updated_children == node.children

        Parser::AST::Node.new(node.type, updated_children)
      end

      def same_node?(left, right)
        left_location = node_location_signature(left)
        right_location = node_location_signature(right)
        return left.equal?(right) unless left_location && right_location

        left_location == right_location
      end

      def replace_child(child, original_node, mutated_node)
        case child
        when Parser::AST::Node
          replace_node(child, original_node, mutated_node)
        when Array
          child.map { |item| replace_child(item, original_node, mutated_node) }
        else
          child
        end
      end

      def method_body(subject_node)
        case subject_node.type
        when :def
          subject_node.children[2]
        when :defs
          subject_node.children[3]
        else
          subject_node
        end
      end

      def parameter_source(mutant)
        args_node = method_arguments(mutant.subject.ast_node)
        return "" unless args_node

        args_node.children.filter_map do |argument|
          parameter_fragment(argument)
        end.join(", ")
      end

      def method_arguments(subject_node)
        case subject_node&.type
        when :def
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
        "#{argument.children[0]} = #{Unparser.unparse(argument.children[1])}"
      end

      def rest_parameter_fragment(argument)
        prefixed_parameter(argument, "*")
      end

      def keyword_parameter_fragment(argument)
        "#{argument.children[0]}:"
      end

      def optional_keyword_parameter_fragment(argument)
        "#{argument.children[0]}: #{Unparser.unparse(argument.children[1])}"
      end

      def keyword_rest_parameter_fragment(argument)
        prefixed_parameter(argument, "**")
      end

      def block_parameter_fragment(argument)
        "&#{argument.children[0]}"
      end

      def forward_parameter_fragment(_argument)
        "..."
      end

      def prefixed_parameter(argument, prefix)
        name = argument.children[0]
        name ? "#{prefix}#{name}" : prefix
      end

      def load_target(subject)
        Object.const_get(subject.namespace.delete_prefix("::"))
      rescue NameError
        load_source_file(subject)
        Object.const_get(subject.namespace.delete_prefix("::"))
      end

      def load_source_file(subject)
        source_file = subject.source_file || source_file_from_ast(subject)
        return unless source_file && File.file?(source_file)

        load(source_file)
      end

      def source_file_from_ast(subject)
        ast_node = subject.ast_node
        return unless ast_node

        location = ast_node.location
        return unless location

        expression = location.expression
        return unless expression

        expression.source_buffer.name
      end

      def node_location_signature(node)
        expression = node&.location&.expression
        return unless expression

        [
          expression.source_buffer.name,
          expression.line,
          expression.column,
          expression.last_line,
          expression.last_column
        ]
      end
    end
  end
end
