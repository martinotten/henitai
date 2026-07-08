# frozen_string_literal: true

require "prism"

module Henitai
  # Reads `# henitai:disable` magic comments from subject source files and
  # decides whether a mutant is excluded from the run.
  #
  # Grammar (backward compatible — a bare directive means "all operators"):
  #
  #   # henitai:disable                          all operators, current scope
  #   # henitai:disable -- prose                 same; `--` introduces prose
  #   # henitai:disable OpA, OpB                 only the named operators
  #   # henitai:disable OpA: reason              reason lands in the report
  #   # henitai:disable: reason                  all operators, with reason
  #   # henitai:disable-start [ops][: reason]    region begin
  #   # henitai:disable-end                      region end
  #
  # Scopes: trailing comment (line), standalone comment directly above a
  # `def` (method), and disable-start/disable-end pairs (region, no nesting).
  # Operator names must exactly match the canonical registry names
  # (`henitai operator list`); unknown names, unmatched or nested region
  # directives raise Henitai::ConfigurationError with file:line.
  #
  # Matching mutants are reported as ignored by {StaticFilter}, not dropped.
  class MutationSkipDirectives
    DIRECTIVE = /\A#\s*henitai:disable(?<kind>-start|-end)?(?<rest>[:\s].*)?\z/
    VALID_OPERATOR_NAMES = Operator::FULL_SET

    # A parsed directive: +operators+ is nil (all) or a Set of canonical
    # operator names; +reason+ is optional free text shown in reports.
    Directive = Data.define(:operators, :reason) do
      def match?(operator)
        operators.nil? || operators.include?(operator.to_s)
      end
    end

    # Per-file directives, classified by scope.
    Index = Data.define(:trailing, :standalone, :regions, :standalone_comment_lines)
    EMPTY_INDEX = Index.new(
      trailing: {}.freeze,
      standalone: {}.freeze,
      regions: [].freeze,
      standalone_comment_lines: Set.new.freeze
    ).freeze

    def initialize
      @index_cache = {}
    end

    def skip?(mutant)
      !directive_for(mutant).nil?
    end

    # @return [Directive, nil] the directive excluding this mutant, if any.
    def directive_for(mutant)
      line_directive_for(mutant) || region_directive_for(mutant) || method_directive_for(mutant)
    end

    private

    def line_directive_for(mutant)
      directive = index_for(mutant.location[:file]).trailing[mutant.location[:start_line]]
      directive&.match?(mutant.operator) ? directive : nil
    end

    def region_directive_for(mutant)
      index = index_for(mutant.location[:file])
      line = mutant.location[:start_line]
      _range, directive = index.regions.find do |range, region_directive|
        range.cover?(line) && region_directive.match?(mutant.operator)
      end
      directive
    end

    def method_directive_for(mutant)
      range = mutant.subject&.source_range
      return nil unless range

      index = index_for(mutant.subject.source_file)
      line = range.begin - 1
      while index.standalone_comment_lines.include?(line)
        directive = index.standalone[line]
        return directive if directive&.match?(mutant.operator)

        line -= 1
      end
      nil
    end

    def index_for(path)
      mtime = File.mtime(path)
      cached_mtime, cached_index = @index_cache[path]
      return cached_index if cached_mtime == mtime

      index = build_index(path)
      @index_cache[path] = [mtime, index]
      index
    rescue Errno::ENOENT, Errno::EACCES
      EMPTY_INDEX
    end

    def build_index(path)
      source = File.read(path)
      lines = source.lines
      builder = IndexBuilder.new(path)

      Prism.parse(source).comments.sort_by { |comment| comment.location.start_line }.each do |comment|
        builder.record(comment, standalone: standalone?(comment, lines))
      end

      builder.index
    end

    def standalone?(comment, lines)
      prefix = lines[comment.location.start_line - 1].to_s[0...comment.location.start_column]
      prefix.strip.empty?
    end

    # Accumulates classified directives for one file, tracking open
    # disable-start regions and raising on malformed directive usage.
    class IndexBuilder
      def initialize(path)
        @path = path
        @trailing = {}
        @standalone = {}
        @regions = []
        @standalone_comment_lines = Set.new
        @open_region = nil
      end

      def record(comment, standalone:)
        line = comment.location.start_line
        @standalone_comment_lines << line if standalone
        match = DIRECTIVE.match(comment.slice)
        return unless match

        dispatch(match, line, standalone)
      end

      def index
        ensure_all_regions_closed!

        Index.new(
          trailing: @trailing.freeze,
          standalone: @standalone.freeze,
          regions: @regions.freeze,
          standalone_comment_lines: @standalone_comment_lines.freeze
        )
      end

      private

      def ensure_all_regions_closed!
        return unless @open_region

        error("unclosed `henitai:disable-start` (opened at line #{@open_region.fetch(:line)})")
      end

      def dispatch(match, line, standalone)
        case match[:kind]
        when "-start" then open_region(parse_payload(match[:rest], line), line)
        when "-end" then close_region(line)
        else
          bucket = standalone ? @standalone : @trailing
          bucket[line] = parse_payload(match[:rest], line)
        end
      end

      def open_region(directive, line)
        error("nested `henitai:disable-start` at line #{line}") if @open_region

        @open_region = { line:, directive: }
      end

      def close_region(line)
        error("`henitai:disable-end` without a matching start at line #{line}") unless @open_region

        @regions << [(@open_region.fetch(:line)..line), @open_region.fetch(:directive)]
        @open_region = nil
      end

      def parse_payload(rest, line)
        text = rest.to_s.strip
        return Directive.new(operators: nil, reason: nil) if prose?(text)
        return Directive.new(operators: nil, reason: presence(text[1..])) if text.start_with?(":")

        operators_part, reason = text.split(":", 2)
        Directive.new(
          operators: parse_operator_names(operators_part, line),
          reason: presence(reason)
        )
      end

      # Free-form rationale after a bare directive stays valid (pre-grammar
      # behavior): empty, `-- prose`, or anything whose first token cannot be
      # an operator name (operators are CamelCase). Only CamelCase-looking
      # tokens are validated against the registry and can raise.
      def prose?(text)
        text.empty? || text.start_with?("--") ||
          (!text.start_with?(":") && !text.match?(/\A[A-Z]/))
      end

      def parse_operator_names(operators_part, line)
        names = operators_part.split(",", -1).map(&:strip)
        names.each do |name|
          next if VALID_OPERATOR_NAMES.include?(name)

          error(
            "unknown operator #{name.inspect} in `henitai:disable` directive at line #{line} " \
            "(valid names: `henitai operator list`)"
          )
        end
        names.to_set
      end

      def presence(text)
        stripped = text.to_s.strip
        stripped.empty? ? nil : stripped
      end

      def error(message)
        raise Henitai::ConfigurationError, "#{@path}: #{message}"
      end
    end
  end
end
