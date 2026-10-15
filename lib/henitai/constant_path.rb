# frozen_string_literal: true

module Henitai
  # Names constants as the source writes them and attributes them to the
  # namespace they belong to, as far as the source alone can tell.
  module ConstantPath
    module_function

    # The constant path of a +const+ or +casgn+ node as written;
    # root-qualified paths keep their leading +::+. nil for other nodes.
    def of(node)
      return unless node.respond_to?(:type)

      case node.type
      when :const, :casgn
        parent = of(node.children[0])
        own = node.children[1].to_s
        parent.nil? ? own : "#{parent}::#{own}"
      when :cbase
        ""
      end
    end

    # +name+ inside +namespace+. A root-qualified name (+::Top+) ignores the
    # enclosing namespace.
    def qualify(namespace, name)
      return name.delete_prefix("::") if name&.start_with?("::")
      return name if namespace.nil? || namespace.empty?
      return namespace if name.nil? || name.empty?

      "#{namespace}::#{name}"
    end

    # The object a singleton method or singleton class is defined on: the
    # enclosing namespace for +self+, the named constant otherwise, nil for
    # any other object. A relative constant is attributed to the innermost
    # lexical candidate, which Ruby also tries first. The source alone cannot
    # tell whether +Other+ inside +module Outer+ is +Outer::Other+ or
    # +::Other+, so this name can be off; activation resolves the real object
    # at runtime (Mutant::Activator).
    def owner(receiver, namespace)
      case receiver.type
      when :self then namespace
      when :const then qualify(namespace, of(receiver))
      end
    end
  end
end
