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

      def self.activate!(mutant)
        new.activate!(mutant)
      end

      # Returns the +define_method+ source string for +mutant+ without
      # actually evaluating it. Used to pre-compute activation recipes.
      # Returns nil if the source cannot be computed (e.g. unsupported AST node).
      def self.activation_source_for(mutant)
        new.send(:method_source, mutant)
      rescue StandardError
        nil
      end

      def activate!(mutant)
        subject = mutant.subject
        raise ArgumentError, "Cannot activate wildcard subjects" if subject.method_name.nil?

        source = mutant.precomputed_activation_source || method_source(mutant)
        target = target_for(subject)
        Henitai::WarningSilencer.silence do
          target.class_eval(source, __FILE__, __LINE__ + 1)
          nil
        end
      rescue Unparser::UnsupportedNodeError, SyntaxError
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
            source_body(location, body)
        else
          expression_source(location, original_range, replacement) ||
            source_body(location, body)
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
        ParameterSource.new.build(mutant.subject.ast_node)
      end

      def block_body(subject_node)
        subject_node.children[2]
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
        loaded_feature = File.expand_path(source_file)
        $LOADED_FEATURES << loaded_feature unless $LOADED_FEATURES.include?(loaded_feature)
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
