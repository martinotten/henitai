# frozen_string_literal: true

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
        target = Object.const_get(subject.namespace.delete_prefix("::"))
        subject.method_type == :class ? target.singleton_class : target
      end

      def method_source(mutant)
        method_name = mutant.subject.method_name
        replacement = Unparser.unparse(mutant.mutated_node)

        <<~RUBY
          define_method(:#{method_name}) do |*args, **kwargs, &block|
            #{replacement}
          end
        RUBY
      end
    end
  end
end
