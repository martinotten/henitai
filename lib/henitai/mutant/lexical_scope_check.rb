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
      SINGLETON_PREFIX = "class << "

      # The lexical nesting (innermost first, ending with Object, mirroring
      # Ruby's cref chain) and the current +self+, which a class_eval block
      # changes without changing the nesting.
      Scope = Data.define(:nesting, :receiver)

      def self.resolves?(openers)
        new.resolves?(openers)
      end

      def resolves?(openers)
        scope = Scope.new(nesting: [Object], receiver: Object)
        openers.all? { |opener| scope = next_scope(opener, scope) }
      end

      private

      def next_scope(opener, scope)
        return singleton_scope(opener, scope) if opener.start_with?(SINGLETON_PREFIX)
        return class_eval_scope(opener, scope) if opener.end_with?(CLASS_EVAL_SUFFIX)

        target = opener_target(opener, scope)
        target && Scope.new(nesting: [target, *scope.nesting], receiver: target)
      end

      # A singleton opener cannot create a constant, but its receiver must
      # resolve; its singleton class becomes both the cref and +self+.
      def singleton_scope(opener, scope)
        found, value = resolve_expression(opener.delete_prefix(SINGLETON_PREFIX), scope)
        return unless found

        singleton = value.singleton_class
        Scope.new(nesting: [singleton, *scope.nesting], receiver: singleton)
      rescue TypeError
        nil
      end

      # A block evaluated with class_eval keeps the enclosing constant lookup
      # and only changes +self+ to its receiver.
      def class_eval_scope(opener, scope)
        found, value = resolve_expression(opener.delete_suffix(CLASS_EVAL_SUFFIX), scope)
        found && value.is_a?(Module) && scope.with(receiver: value)
      end

      def opener_target(opener, scope)
        kind, path = opener.split(" ", 2)
        segments = path.delete_prefix("::").split("::")
        parent = path.start_with?("::") ? walk(Object, segments[0...-1]) : parent_of(segments[0...-1], scope)
        value = parent.is_a?(Module) && constant_value(parent, segments.last)
        value if matches_kind?(value, kind)
      end

      # Resolves a constant expression such as +Point+, +self::Inner+ or
      # +::Outer::Point+. Returns whether it resolved and its value.
      def resolve_expression(path, scope)
        return [true, scope.receiver] if path == "self"

        value = path.match?(/\A\w+\z/) ? lexical_lookup(path, scope.nesting) : qualified_value(path, scope)
        [!value.nil?, value]
      end

      def qualified_value(path, scope)
        segments = path.delete_prefix("::").split("::")
        base = path.start_with?("::") ? Object : parent_of(segments.first(1), scope)
        walk(base, segments.drop(path.start_with?("::") ? 0 : 1))
      end

      # A leading +self+ (as in +class self::Inner+) is the current receiver.
      def parent_of(segments, scope)
        return scope.nesting.first if segments.empty?

        first = segments.first == "self" ? scope.receiver : lexical_lookup(segments.first, scope.nesting)
        walk(first, segments.drop(1))
      end

      def walk(base, segments)
        segments.reduce(base) { |current, name| current.is_a?(Module) ? own_constant(current, name) : nil }
      end

      # Ruby's order: the own constants of each lexical scope (innermost
      # first, without Object), then the ancestors of the innermost scope,
      # then the top level.
      def lexical_lookup(name, nesting)
        scope = nesting[0...-1].find { |candidate| candidate.const_defined?(name, false) }
        return scope.const_get(name, false) if scope

        innermost = nesting.first
        innermost.const_get(name) if innermost.const_defined?(name) || Object.const_defined?(name)
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
