# frozen_string_literal: true

module Henitai
  class Mutant
    # Resolves the object a re-evaluated +def+ must be defined on, and loads
    # the subject's source file when its namespace is still undefined.
    class LexicalTarget
      # Raised when a subject's namespace is still undefined after its source
      # file was loaded, so there is no class to reopen.
      class SubjectNotLoadedError < StandardError; end

      def self.resolve(subject, activation)
        new.resolve(subject, activation)
      end

      def self.load_target(subject)
        new.load_target(subject)
      end

      # The object the re-evaluated +def+ defines its method on, as Ruby
      # resolves it: the openers are evaluated with +self+ -- or the receiver
      # of +def Other.name+ -- as their body. The subject's namespace is only
      # the resolver's static reading of the source, which cannot tell
      # whether +Other+ inside +module Outer+ is +Outer::Other+ or +::Other+.
      # The scope, owner and singleton flag come from the activation, so a
      # replayed recipe does not need the AST. The subject's file is loaded
      # first when needed (see +ensure_loaded+), so that evaluating the openers
      # reopens the loaded class instead of creating an empty one.
      def resolve(subject, activation)
        scope = activation.lexical_scope
        ensure_loaded(subject, scope)
        source = "#{scope.join('; ')}\n#{activation.owner}\n#{Array.new(scope.size, 'end').join('; ')}"
        owner = TOPLEVEL_BINDING.eval(source, activation.file, activation.line)
        activation.singleton ? owner.singleton_class : owner
      end

      def load_target(subject)
        Object.const_get(subject.namespace.delete_prefix("::"))
      rescue NameError
        load_source_file(subject)
        Object.const_get(subject.namespace.delete_prefix("::"))
      end

      private

      # Evaluating the openers must reopen existing constants, never create
      # them: a missing class would become an empty phantom that swallows the
      # mutant. The scope is therefore checked without evaluation first. If it
      # does not resolve, the subject's file is loaded and checked again. If it
      # still does not resolve, activation fails instead of creating anything.
      def ensure_loaded(subject, scope)
        return load_toplevel_source(subject) if scope.empty?
        return if LexicalScopeCheck.resolves?(scope)

        load_subject_source(subject)
        return if LexicalScopeCheck.resolves?(scope)

        raise SubjectNotLoadedError,
              "cannot activate #{subject.expression}: its source did not define #{subject.namespace}"
      end

      # Without openers no phantom class can be created; the file is loaded
      # only when the subject's namespace constant is still missing. A file
      # that fails to load fails the activation instead of crashing the child.
      def load_toplevel_source(subject)
        load_target(subject)
      rescue NameError
        nil
      rescue StandardError, ScriptError => e
        raise SubjectNotLoadedError, "cannot activate #{subject.namespace}: its source failed to load (#{e.message})"
      end

      def load_subject_source(subject)
        load_source_file(subject)
      rescue StandardError, ScriptError => e
        raise SubjectNotLoadedError, "cannot activate #{subject.namespace}: its source failed to load (#{e.message})"
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
    end
  end
end
