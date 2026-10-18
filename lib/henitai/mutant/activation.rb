# frozen_string_literal: true

module Henitai
  class Mutant
    # The Ruby source that puts a mutant in place, and how to evaluate it.
    #
    # +mode+ is :toplevel for a real +def+ re-evaluated inside the original
    # module and class openers (ADR-13), evaluated at the top level with
    # +file+ and +line+ so +__FILE__+, +__LINE__+ and backtraces stay those of
    # the original source; +def_offset+ is the index of the +def+ line within
    # +source+. +mode+ is :class_eval for the +define_method+ fallback,
    # evaluated inside the target module.
    #
    # For :toplevel, +lexical_scope+ holds the opener lines (e.g. "module A",
    # "class B"), +owner+ the expression the +def+ is defined on ("self" or
    # the receiver of +def Other.name+), and +singleton+ whether it is a
    # +defs+. They let a replayed recipe reopen the scope without the AST.
    Activation = Struct.new(:source, :mode, :file, :line, :def_offset, :lexical_scope, :owner, :singleton,
                            keyword_init: true) do
      def self.from_h(hash)
        new(source: hash.fetch("source"), mode: hash.fetch("mode").to_sym, file: hash["file"],
            line: hash["line"], def_offset: hash["defOffset"], lexical_scope: hash["lexicalScope"],
            owner: hash["owner"], singleton: hash["singleton"])
      end

      def to_h
        { "source" => source, "mode" => mode.to_s, "file" => file, "line" => line, "defOffset" => def_offset,
          "lexicalScope" => lexical_scope, "owner" => owner, "singleton" => singleton }
      end
    end
  end
end
