# frozen_string_literal: true

require_relative "source_parser"
require_relative "subject"
require_relative "constant_path"

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

    def apply_pattern(subjects, pattern)
      pattern_subject = Subject.parse(pattern)

      Array(subjects).select do |subject|
        match_subject?(subject, pattern_subject)
      end
    end

    private

    def resolve_from_file(path)
      @scope = []
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
      return walk_constructor_body(node, namespace, subjects) if constructor_assignment?(node)
      return if anonymous_class_block?(node)

      namespace, singleton_context = update_context(
        node,
        namespace,
        singleton_context
      )

      within_scope(node) do
        collect_subject(node, namespace, singleton_context, subjects)
        traverse_children(node, namespace, singleton_context, subjects)
      end
    end

    # +Point = Struct.new(:x) do ... end+: the block is evaluated with
    # class_eval on the new class, so its methods belong to +Point+ while
    # constant lookup stays in the enclosing scope. +Point.class_eval do+
    # reproduces exactly that when the method is re-evaluated.
    def walk_constructor_body(node, namespace, subjects)
      @scope.push("#{assigned_constant_source(node)}.class_eval do")
      walk(node.children[2].children[2], namespace: ConstantPath.qualify(namespace, ConstantPath.of(node)),
                                         singleton_context: false, subjects:)
    ensure
      @scope.pop
    end

    def constructor_assignment?(node)
      node.type == :casgn && anonymous_class_block?(node.children[2])
    end

    def assigned_constant_source(node)
      node.location.expression.begin.join(node.location.name).source
    end

    # Tracks the openers of the modules and classes around the walk position,
    # so a method can later be re-evaluated in its original lexical scope.
    def within_scope(node)
      opener = scope_opener(node)
      @scope.push(opener) unless opener == :none
      yield
    ensure
      @scope.pop unless opener == :none
    end

    def scope_opener(node)
      case node.type
      when :class, :module then "#{node.type} #{node.children.first.location.expression.source}"
      when :sclass then singleton_opener(node.children.first)
      else :none
      end
    end

    def singleton_opener(receiver)
      case receiver.type
      when :self then "class << self"
      when :const then "class << #{receiver.location.expression.source}"
      end
    end

    # nil when some enclosing scope cannot be reopened by name (class << obj).
    def lexical_scope
      @scope.include?(nil) ? nil : @scope.dup
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

    def anonymous_class_block?(node)
      return false unless node.type == :block

      call_node = node.children.first
      return false unless call_node.respond_to?(:type)
      return false unless call_node.type == :send

      receiver = call_node.children.first
      method_name = call_node.children[1]
      receiver_name = ConstantPath.of(receiver)&.delete_prefix("::")

      anonymous_constructor_call?(receiver_name, method_name)
    end

    def anonymous_constructor_call?(receiver_name, method_name)
      anonymous_receivers = %w[Class Module Struct Data]
      anonymous_methods = %i[new define]

      anonymous_receivers.include?(receiver_name) &&
        anonymous_methods.include?(method_name)
    end

    def update_context(node, namespace, singleton_context)
      case node.type
      when :class, :module
        [ConstantPath.qualify(namespace, ConstantPath.of(node.children.first)),
         singleton_context]
      when :sclass
        [ConstantPath.owner(node.children.first, namespace), true]
      else
        [namespace, singleton_context]
      end
    end

    def subject_for(node, namespace, singleton_context)
      case node.type
      when :block
        define_method_subject(node, namespace, singleton_context)
      when :def
        instance_subject(node, namespace, singleton_context)
      when :defs
        class_subject(node, ConstantPath.owner(node.children.first, namespace))
      end
    end

    def instance_subject(node, namespace, singleton_context)
      return unless namespace

      Subject.new(
        namespace:,
        method_name: method_name(node.children.first),
        method_type: singleton_context ? :class : :instance,
        source_location: source_location_for(node),
        ast_node: node,
        lexical_scope:
      )
    end

    def class_subject(node, namespace)
      return unless namespace

      Subject.new(
        namespace:,
        method_name: method_name(node.children[1]),
        method_type: :class,
        source_location: source_location_for(node),
        ast_node: node,
        lexical_scope:
      )
    end

    def define_method_subject(node, namespace, singleton_context)
      call_node = node.children.first
      return unless define_method_call?(call_node)
      return unless namespace

      method_name = define_method_name(call_node)
      return unless method_name

      Subject.new(
        namespace:,
        method_name:,
        method_type: singleton_context ? :class : :instance,
        source_location: source_location_for(node),
        ast_node: node
      )
    end

    def method_name(value)
      symbol_name(value)
    end

    def define_method_call?(call_node)
      return false unless call_node.respond_to?(:type)
      return false unless call_node.type == :send
      return false unless call_node.children[1] == :define_method

      receiver = call_node.children.first
      receiver.nil? || receiver.type == :self
    end

    def define_method_name(call_node)
      literal_method_name(call_node.children[2])
    end

    def literal_method_name(node)
      return unless node.respond_to?(:type)

      case node.type
      when :sym, :str
        symbol_name(node.children.first)
      end
    end

    def symbol_name(value)
      # Prism exposes identifiers as symbols (for example, :foo), so normalize
      # them to the string form used by Subject expressions.
      value.to_s.delete_prefix(":")
    end

    def source_location_for(node)
      location = node.location.expression

      {
        file: location.source_buffer.name,
        range: location.line..location.last_line
      }
    end

    def match_subject?(subject, pattern_subject)
      if pattern_subject.wildcard?
        wildcard_match?(subject, pattern_subject)
      else
        subject.expression == pattern_subject.expression
      end
    end

    def wildcard_match?(subject, pattern_subject)
      subject_namespace = subject.namespace
      pattern_namespace = pattern_subject.namespace

      return false unless subject_namespace

      subject_namespace == pattern_namespace ||
        subject_namespace.start_with?("#{pattern_namespace}::")
    end
  end
end
