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
    Activation = Struct.new(:source, :mode, :file, :line, :def_offset, keyword_init: true) do
      def self.from_h(hash)
        new(source: hash.fetch("source"), mode: hash.fetch("mode").to_sym, file: hash["file"],
            line: hash["line"], def_offset: hash["defOffset"])
      end

      def to_h
        { "source" => source, "mode" => mode.to_s, "file" => file, "line" => line, "defOffset" => def_offset }
      end
    end
  end
end
