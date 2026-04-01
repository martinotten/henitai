# frozen_string_literal: true

require "parser/current"
require "unparser"

module Henitai
  class Mutant
    # Activates a mutant inside the forked child process.
    class Activator
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
        replacement = body_source(mutant)

        <<~RUBY
          define_method(:#{method_name}) do |*args, **kwargs, &block|
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
