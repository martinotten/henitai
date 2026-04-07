# frozen_string_literal: true

require_relative "../parser_current"
require "unparser"

module Henitai
  class Mutant
    # Activates a mutant inside the forked child process.
    class Activator
      # Filters "already initialized constant" C-level warnings that fire when
      # a source file is loaded into a process that already has the constant
      # defined via require. Uses a thread-local flag so the filter is active
      # only during load_source_file, leaving all other warnings untouched.
      module ConstantRedefinitionFilter
        PATTERN = /already initialized constant|previous definition of/
        private_constant :PATTERN

        def warn(msg, **kwargs)
          return if Thread.current[:henitai_filter_const_warnings] && PATTERN.match?(msg.to_s)

          super
        end
      end
      Warning.singleton_class.prepend(ConstantRedefinitionFilter)

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

        target = target_for(subject)
        Henitai::WarningSilencer.silence do
          target.class_eval(method_source(mutant), __FILE__, __LINE__ + 1)
          nil
        end
      rescue Unparser::UnsupportedNodeError
        :compile_error
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
        return compile_safe_unparse(mutant.mutated_node) unless subject_node

        body = method_body(subject_node)
        return compile_safe_unparse(Parser::AST::Node.new(:nil, [])) unless body

        body_source_for_mutant(body, mutant)
      end

      def body_source_for_mutant(body, mutant)
        original_range = mutant.original_node.location&.expression
        location = body.location
        return source_body(location, body) unless original_range && location

        replacement = compile_safe_unparse(mutant.mutated_node)
        body_source_for_location(location, original_range, replacement, body)
      end

      def body_source_for_location(location, original_range, replacement, body)
        if heredoc_location?(location)
          heredoc_body_source(location, original_range, replacement) ||
            source_body(location, body) ||
            compile_safe_unparse(body)
        else
          expression_source(location, original_range, replacement) ||
            source_body(location, body) ||
            compile_safe_unparse(body)
        end
      end

      def method_body(subject_node)
        case subject_node.type
        when :def
          subject_node.children[2]
        when :defs
          subject_node.children[3]
        when :block
          block_body(subject_node)
        else
          subject_node
        end
      end

      def parameter_source(mutant)
        args_node = method_arguments(mutant.subject.ast_node)
        return "" unless args_node
        return forward_parameter_fragment(nil) if args_node.type == :forward_args

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
        when :block
          block_arguments(subject_node)
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

      def block_body(subject_node)
        subject_node.children[2]
      end

      def block_arguments(subject_node)
        subject_node.children[1]
      end

      def heredoc_location?(location)
        location.respond_to?(:heredoc_body) && location.heredoc_body
      end

      def heredoc_body_source(location, original_range, replacement)
        body_source = replace_source_fragment(
          location.heredoc_body,
          original_range,
          replacement
        )
        return unless body_source

        "#{location.expression.source}\n#{body_source}#{location.heredoc_end.source}"
      end

      def source_body(location, body)
        return compile_safe_unparse(body) unless location

        if heredoc_location?(location)
          "#{location.expression.source}\n#{location.heredoc_body.source}#{location.heredoc_end.source}"
        else
          location.expression.source
        end
      end

      def expression_source(location, original_range, replacement)
        source_range = location.expression
        return unless source_range

        replace_source_fragment(source_range, original_range, replacement)
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

        Thread.current[:henitai_filter_const_warnings] = true
        load(source_file)
      ensure
        Thread.current[:henitai_filter_const_warnings] = false
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

      def replace_source_fragment(source_range, original_range, replacement)
        source = source_range.source
        start = original_range.begin_pos - source_range.begin_pos
        stop = original_range.end_pos - source_range.begin_pos
        return unless start >= 0 && stop <= source.bytesize && start <= stop

        prefix = source.byteslice(0, start)
        suffix = source.byteslice(stop, source.bytesize - stop)
        return unless prefix && suffix

        prefix + replacement + suffix
      end

      def compile_safe_unparse(node)
        Unparser.unparse(node)
      rescue StandardError => e
        raise Unparser::UnsupportedNodeError, e.message
      end
    end
  end
end
