# frozen_string_literal: true

module Henitai
  class Mutant
    # Builds the :toplevel activation for a mutant (ADR-13): the subject's
    # own +def+, with the mutation spliced in, wrapped in the module and class
    # openers that surround it in the source.
    #
    # Re-evaluating a real +def+ in its lexical scope keeps everything a
    # +define_method+ block loses: constant lookup through the enclosing
    # modules, implicit +super+, +yield+ and +block_given?+, the exact
    # parameter list, +__FILE__+ and +__LINE__+, and the file's
    # +frozen_string_literal+ comment. Visibility is restored by the Activator.
    #
    # Returns nil when the subject cannot be reopened this way (a
    # +define_method+ subject, a method in +class << obj+, a subject without
    # recorded scope); the Activator then falls back to +define_method+.
    class DefInjection
      MAGIC_COMMENT = /\A#.*\b(frozen_string_literal|shareable_constant_value|warn_indent)\s*:/i

      def self.build(mutant, replacement)
        new.build(mutant, replacement)
      end

      def build(mutant, replacement)
        subject = mutant.subject
        node = subject.ast_node
        scope = subject.lexical_scope
        return unless injectable?(node, scope)

        def_source = spliced_def(node.location.expression, mutant.original_node, replacement)
        return unless def_source

        assemble(node.location.expression, scope, def_source)
      end

      private

      # A top-level +def Other.name+ has no openers; an instance method needs
      # at least one, or it would land on Object.
      def injectable?(node, scope)
        return false unless node && scope

        node.type == :defs || (node.type == :def && !scope.empty?)
      end

      # Splices by character offsets, as parser ranges count characters. A
      # heredoc's expression range covers only its opener, so the bodies of
      # heredocs inside the replaced node are removed as well; otherwise they
      # would stay behind as code.
      def spliced_def(def_range, original_node, replacement)
        original_range = original_node&.location&.expression
        return unless original_range && within?(original_range, def_range)

        edits = heredoc_bodies(original_node).map { |range| [range, ""] } << [original_range, replacement]
        apply(def_range, edits)
      end

      # Applies non-overlapping edits from the last to the first, so earlier
      # offsets stay valid.
      def apply(def_range, edits)
        edits.sort_by { |range, _| -range.begin_pos }.each_with_object(def_range.source.dup) do |(range, insert), text|
          start = range.begin_pos - def_range.begin_pos
          text[start...(range.end_pos - def_range.begin_pos)] = insert
        end
      end

      def heredoc_bodies(node)
        return [] unless node.is_a?(Parser::AST::Node)

        own = node.location.respond_to?(:heredoc_body) && node.location.heredoc_body
        bodies = own ? [own.join(node.location.heredoc_end)] : []
        bodies + node.children.flat_map { |child| heredoc_bodies(child) }
      end

      def within?(inner, outer)
        inner.begin_pos.between?(outer.begin_pos, inner.end_pos) && inner.end_pos <= outer.end_pos
      end

      def assemble(def_range, scope, def_source)
        prefix = magic_comments(def_range.source_buffer.source) + [scope.join("; ")]
        Activation.new(source: source_lines(prefix, def_range, scope, def_source), mode: :toplevel,
                       file: File.expand_path(def_range.source_buffer.name),
                       line: def_range.line - prefix.size, def_offset: prefix.size)
      end

      def source_lines(prefix, def_range, scope, def_source)
        lines = prefix + ["#{' ' * def_range.column}#{def_source}", Array.new(scope.size, "end").join("; ")]
        "#{lines.join("\n")}\n"
      end

      def magic_comments(file_source)
        header = file_source.each_line.take_while { |line| line.strip.empty? || line.start_with?("#") }
        header.map(&:chomp).grep(MAGIC_COMMENT)
      end
    end
  end
end
