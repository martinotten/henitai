# frozen_string_literal: true

module Henitai
  class Mutant
    # Decides whether the scope openers of an activation can be reopened.
    #
    # Evaluating an opener such as "class Inner" creates the class when it is
    # missing, which would inject a mutant into an empty phantom class. This
    # check walks the openers the way Ruby resolves them, but never evaluates
    # them, so it never defines a constant.
    class LexicalScopeCheck
      CLASS_EVAL_SUFFIX = ".class_eval do"

      def self.resolves?(openers)
        new.resolves?(openers)
      end

      # The nesting is innermost first and always ends with Object, mirroring
      # Ruby's cref chain. A singleton opener cannot create a class, so the
      # walk ends there.
      def resolves?(openers)
        nesting = [Object]
        openers.each do |opener|
          return true if opener.start_with?("class <<")

          nesting = next_nesting(opener, nesting)
          return false unless nesting
        end
        true
      end

      private

      def next_nesting(opener, nesting)
        return class_eval_nesting(opener, nesting) if opener.end_with?(CLASS_EVAL_SUFFIX)

        target = opener_target(opener, nesting)
        target && [target, *nesting]
      end

      # A block evaluated with class_eval keeps the enclosing constant lookup,
      # so only its receiver has to resolve.
      def class_eval_nesting(opener, nesting)
        receiver = opener.delete_suffix(CLASS_EVAL_SUFFIX)
        nesting if resolve_path(receiver, nesting)
      end

      def opener_target(opener, nesting)
        kind, path = opener.split(" ", 2)
        value = resolve_path(path, nesting)
        value if value && matches_kind?(value, kind)
      end

      def resolve_path(path, nesting)
        segments = path.delete_prefix("::").split("::")
        parent = path.start_with?("::") ? Object : parent_of(segments[0...-1], nesting)
        parent && constant_value(parent, segments.last)
      end

      # A leading +self+ (as in +class self::Inner+) is the innermost scope.
      def parent_of(segments, nesting)
        return nesting.first if segments.empty?

        first = segments.first == "self" ? nesting.first : lexical_lookup(segments.first, nesting)
        segments.drop(1).reduce(first) { |base, name| base && own_constant(base, name) }
      end

      def lexical_lookup(name, nesting)
        scope = nesting.find { |candidate| candidate.const_defined?(name, false) }
        scope&.const_get(name, false)
      end

      def own_constant(base, name)
        base.const_get(name, false) if base.const_defined?(name, false)
      end

      def constant_value(parent, name)
        inherit = parent.equal?(Object)
        parent.const_get(name, inherit) if parent.const_defined?(name, inherit)
      end

      def matches_kind?(value, kind)
        return false unless value.is_a?(Module)

        kind == "class" ? value.is_a?(Class) : !value.is_a?(Class)
      end
    end
  end
end
