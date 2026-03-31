# frozen_string_literal: true

require_relative "source_parser"
require_relative "subject"

module Henitai
  # Resolves AST subjects from Ruby source files.
  #
  # The resolver walks Prism-translated ASTs and extracts method definitions
  # with the namespace context established by surrounding module/class nodes.
  class SubjectResolver
    def resolve_from_files(paths)
      Array(paths).flat_map do |path|
        resolve_from_file(path)
      end
    end

    private

    def resolve_from_file(path)
      subjects = []
      walk(
        SourceParser.parse_file(path),
        namespace: nil,
        singleton_context: false,
        subjects:
      )
      subjects
    end

    def walk(node, namespace:, singleton_context:, subjects:)
      return unless node.respond_to?(:type)

      namespace, singleton_context = update_context(
        node,
        namespace,
        singleton_context
      )

      collect_subject(node, namespace, singleton_context, subjects)
      traverse_children(node, namespace, singleton_context, subjects)
    end

    def collect_subject(node, namespace, singleton_context, subjects)
      subject = subject_for(node, namespace, singleton_context)
      subjects << subject if subject
    end

    def traverse_children(node, namespace, singleton_context, subjects)
      node.children.each do |child|
        walk(child, namespace:, singleton_context:, subjects:)
      end
    end

    def update_context(node, namespace, singleton_context)
      case node.type
      when :class, :module
        [qualify_namespace(namespace, constant_name(node.children.first)),
         singleton_context]
      when :sclass
        [namespace, true]
      else
        [namespace, singleton_context]
      end
    end

    def subject_for(node, namespace, singleton_context)
      case node.type
      when :def
        instance_subject(node, namespace, singleton_context)
      when :defs
        class_subject(node, namespace)
      end
    end

    def instance_subject(node, namespace, singleton_context)
      return unless namespace

      Subject.new(
        namespace:,
        method_name: method_name(node.children.first),
        method_type: singleton_context ? :class : :instance,
        source_location: source_location_for(node)
      )
    end

    def class_subject(node, namespace)
      return unless namespace

      Subject.new(
        namespace:,
        method_name: method_name(node.children[1]),
        method_type: :class,
        source_location: source_location_for(node)
      )
    end

    def qualify_namespace(namespace, name)
      return name if namespace.nil? || namespace.empty?
      return namespace if name.nil? || name.empty?

      "#{namespace}::#{name}"
    end

    def constant_name(node)
      return unless node.respond_to?(:type)

      case node.type
      when :const
        parent_name = constant_name(node.children.first)
        current_name = symbol_name(node.children.last)

        return current_name if parent_name.nil? || parent_name.empty?

        "#{parent_name}::#{current_name}"
      when :cbase
        ""
      end
    end

    def method_name(value)
      symbol_name(value)
    end

    def symbol_name(value)
      value.to_s.delete_prefix(":")
    end

    def source_location_for(node)
      location = node.location.expression

      {
        file: location.source_buffer.name,
        range: location.line..location.last_line
      }
    end
  end
end
