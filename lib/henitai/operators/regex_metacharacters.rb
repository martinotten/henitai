# frozen_string_literal: true

module Henitai
  module Operators
    # Locates the regexp metacharacters that RegexMutator edits.
    #
    # An escaped character and the contents of a character class are literal
    # text: the +^+ in +[^0-9]+ negates the class and is no anchor, and the
    # +++ in +[+-]+ or +\++ is no quantifier. The scan therefore skips
    # escapes and tracks character-class nesting, including POSIX brackets
    # such as +[[:alpha:]]+.
    class RegexMetacharacters
      ANCHORS = %w[^ $].freeze
      QUANTIFIERS = %w[+ * ?].freeze
      GROUPING = %w[( |].freeze

      def initialize(source)
        @source = source
        @found = Hash.new { |hash, key| hash[key] = [] }
        scan
      end

      # Indices of the +char+ quantifier ("+" or "*") applied to an atom.
      def quantifiers(char)
        @found[[:quantifier, char]].dup
      end

      # Indices of the +char+ anchor ("^" or "$").
      def anchors(char)
        @found[[:anchor, char]].dup
      end

      # Indices of the opening brackets of top-level, non-negated classes.
      def class_openers
        @found[:class_opener].dup
      end

      private

      def scan
        @index = 0
        @depth = 0
        @previous = nil
        step while @index < @source.length
      end

      def step
        char = @source[@index]
        if char == "\\"
          @previous = :atom
          @index += 2
        else
          @depth.positive? ? within_class(char) : top_level(char)
          @index += 1
        end
      end

      def within_class(char)
        @depth += 1 if char == "["
        @depth -= 1 if char == "]"
        @previous = :atom if @depth.zero?
      end

      def top_level(char)
        record(char)
        @previous = kind_of_token(char)
        @depth = 1 if char == "["
      end

      def record(char)
        if ANCHORS.include?(char)
          @found[[:anchor, char]] << @index
        elsif char == "["
          @found[:class_opener] << @index unless @source[@index + 1] == "^"
        elsif QUANTIFIERS.include?(char) && @previous == :atom
          @found[[:quantifier, char]] << @index
        end
      end

      def kind_of_token(char)
        return :anchor if ANCHORS.include?(char)
        return :quantifier if QUANTIFIERS.include?(char) || char == "}"
        return :group if GROUPING.include?(char)

        :atom
      end
    end
  end
end
