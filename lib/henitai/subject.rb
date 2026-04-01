# frozen_string_literal: true

module Henitai
  # Represents an addressable unit of source code to be mutated.
  #
  # Subjects are expressed using a compact syntax:
  #   Foo::Bar#instance_method    — specific instance method
  #   Foo::Bar.class_method       — specific class method
  #   Foo::Bar*                   — all methods on Foo::Bar
  #   Foo*                        — all methods in the Foo namespace
  #
  # The Subject is resolved from the AST before mutation begins.
  # Test selection uses longest-prefix matching against example group
  # descriptions in the test suite.
  class Subject
    attr_reader :namespace, :method_name, :method_type, :source_file,
                :source_range, :ast_node

    # @param expression [String] subject expression, e.g. "Foo::Bar#method"
    def self.parse(expression)
      new(expression:)
    end

    # @param namespace   [String]  fully-qualified module/class name
    # @param method_name [String]  method name (nil for wildcard subjects)
    # @param method_type [Symbol]  :instance or :class
    # @param source_location [Hash] file/range metadata for the subject source
    def initialize(expression: nil, namespace: nil, method_name: nil,
                   method_type: :instance, **options)
      if expression
        parse_expression(expression)
      else
        @namespace   = namespace
        @method_name = method_name
        @method_type = method_type
      end
      source_location = options[:source_location]
      @source_file  = source_location&.fetch(:file, nil)
      @source_range = source_location&.fetch(:range, nil)
      @ast_node = options[:ast_node]
    end

    # Full addressable expression, e.g. "Foo::Bar#method"
    def expression
      sep = @method_type == :class ? "." : "#"
      @method_name ? "#{@namespace}#{sep}#{@method_name}" : "#{@namespace}*"
    end

    def wildcard?
      @method_name.nil?
    end

    private

    def parse_expression(expr)
      if (m = expr.match(/\A(.+?)([#.])(\w+)\z/))
        @namespace   = m[1]
        @method_type = m[2] == "." ? :class : :instance
        @method_name = m[3]
      else
        # Wildcard: "Foo*" or "Foo::Bar*"
        @namespace   = expr.delete_suffix("*")
        @method_name = nil
        @method_type = :instance
      end
    end
  end
end
