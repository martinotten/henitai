# frozen_string_literal: true

require_relative "../parser_current"
require "unparser"

module Henitai
  class Mutant
    # Activates a mutant inside the forked child process.
    class Activator
      SubjectNotLoadedError = LexicalTarget::SubjectNotLoadedError

      # File name the activation source is evaluated under. It decides what
      # +__FILE__+ and +__LINE__+ mean inside an activated mutant.
      EVAL_FILE = __FILE__

      # Filters "already initialized constant" C-level warnings that fire when
      # a source file is loaded into a process that already has the constant
      # defined via require. Uses a thread-local flag so the filter is active
      # only during LexicalTarget#load_source_file, leaving all other warnings untouched.
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

      # Returns the Activation for +mutant+ without evaluating it: a real
      # +def+ in the original lexical scope when the subject can be reopened
      # (ADR-13), otherwise the +define_method+ fallback. Used by the fidelity
      # check and to pre-compute activation recipes. Returns nil if the source
      # cannot be computed (e.g. unsupported AST node).
      def self.activation_for(mutant)
        new.activation_for(mutant)
      rescue StandardError
        nil
      end

      def self.activation_source_for(mutant)
        activation_for(mutant)&.source
      end

      def activation_for(mutant)
        DefInjection.build(mutant, def_replacement(mutant)) ||
          Activation.new(source: method_source(mutant), mode: :class_eval, file: EVAL_FILE)
      end

      def activate!(mutant)
        subject = mutant.subject
        raise ArgumentError, "Cannot activate wildcard subjects" if subject.method_name.nil?

        activation = mutant.precomputed_activation || activation_for(mutant)
        target = activation.mode == :toplevel ? LexicalTarget.resolve(subject, activation) : target_for(subject)
        Henitai::WarningSilencer.silence do
          evaluate(activation, target, subject)
          nil
        end
      rescue Unparser::UnsupportedNodeError, SyntaxError
        :compile_error
      end

      private

      def evaluate(activation, target, subject)
        return inject_def(activation, target, subject) if activation.mode == :toplevel

        target.class_eval(activation.source, EVAL_FILE, __LINE__)
      end

      # A re-evaluated +def+ is public, so the method's visibility -- or its
      # +module_function+ copy -- is read before and restored after. +target+
      # is already the singleton class for a class method.
      def inject_def(activation, target, subject)
        name = subject.method_name.to_sym
        visibility = visibility_of(target, name)
        copy = module_function_copy?(target, name, subject)
        TOPLEVEL_BINDING.eval(activation.source, activation.file, activation.line)
        return target.send(:module_function, name) if copy

        target.send(visibility, name) if visibility
      end

      def visibility_of(owner, name)
        return :private if owner.private_method_defined?(name)

        :protected if owner.protected_method_defined?(name)
      end

      def module_function_copy?(target, name, subject)
        subject.method_type == :instance && !target.is_a?(Class) &&
          target.private_method_defined?(name) && target.singleton_class.method_defined?(name) &&
          target.instance_method(name).source_location == target.method(name).source_location
      end

      def def_replacement(mutant)
        original_range = mutant.original_node&.location&.expression
        replacement_source(mutant, original_range) if original_range
      end

      def target_for(subject)
        target = LexicalTarget.load_target(subject)
        subject.method_type == :class ? target.singleton_class : target
      end

      # The trailing module_function re-copy handles module_function subjects:
      # module_function copies the (private) instance method onto the module's
      # singleton, and define_method only replaces the instance side — without
      # the re-copy, callers of Module.method keep running the original code
      # and every mutant in such modules falsely survives. The guard checks
      # the pre-injection shape (private instance + singleton method on a
      # non-Class module) so a class-level method that merely shares an
      # instance method's name is never clobbered.
      def method_source(mutant)
        method_name = mutant.subject.method_name
        parameters = parameter_source(mutant)
        replacement = body_source(mutant)

        <<~RUBY
          __henitai_module_function__ = !is_a?(Class) &&
            private_method_defined?(:#{method_name}) &&
            singleton_class.method_defined?(:#{method_name}) &&
            instance_method(:#{method_name}).source_location == method(:#{method_name}).source_location
          define_method(:#{method_name}) do |#{parameters}|
            #{replacement}
          end
          module_function :#{method_name} if __henitai_module_function__
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

        body_source_for_location(location, original_range, replacement_source(mutant, original_range), body)
      end

      # An unmutated control keeps the original text: re-rendering it would
      # test the unparser, not the activation path.
      def replacement_source(mutant, original_range)
        Replacement.render(mutant, original_range)
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
        replace_source_fragment(location.expression, original_range, replacement)
      end

      def replace_source_fragment(source_range, original_range, replacement)
        source = source_range.source
        start = original_range.begin_pos - source_range.begin_pos
        stop = original_range.end_pos - source_range.begin_pos
        return unless start >= 0 && stop <= source.length && start <= stop

        source[0, start] + replacement + source[stop..]
      end

      def compile_safe_unparse(node)
        Unparser.unparse(node)
      rescue StandardError => e
        raise Unparser::UnsupportedNodeError, e.message
      end
    end
  end
end
