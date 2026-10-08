# frozen_string_literal: true

require "prism"
require_relative "parser_current"
require_relative "source_parser"

module Henitai
  # Verifies, before a mutant runs, that its activation source differs from
  # the original method by exactly the reported mutation and nothing else.
  #
  # The checks run in order:
  #
  # 1. Site: the mutated node must lie inside the method body that the
  #    activation replaces.
  # 2. Syntax: the activation source must be valid Ruby in context. Prism's
  #    error list is used because the parser translation layer recovers from
  #    errors silently.
  # 3. Structure: the activated method body, re-parsed, must equal the
  #    original body with the original node replaced by the mutated node.
  #    Both sides are normalised first: an interpolation-free +dstr+ is the
  #    same value as one +str+, nested statement sequences flatten, and
  #    +__FILE__+ compares as an absolute path.
  # 4. Syntax form: the legacy AST format the pipeline uses cannot tell some
  #    constructs apart (keyword arguments vs. a braced hash, +|x|+ vs.
  #    +|x,|+). A modern-format parse of both sides must show the same of
  #    these forms at every source range the mutant kept from the original.
  #
  # A violation is a harness defect, not a test verdict: the mutant must not
  # run, and the reason must be reported.
  class FidelityCheck
    # Modern-format node types whose legacy encoding is shared with a construct
    # of different meaning. Forms that re-render into an equivalent call are
    # deliberately absent: `->` vs. `lambda`, and `a[i]` vs. `a.[](i)`.
    FORMAT_TYPES = %i[kwargs procarg0 forward_arg match_pattern match_pattern_p].freeze

    # Parser builder that emits the modern AST format.
    class ModernBuilder < Prism::Translation::Parser::Builder
      modernize
    end

    def initialize
      @format_index_cache = {}
    end

    # @return [String, nil] the reason the mutant is unfaithful, or nil
    def violation(mutant)
      return unless checkable?(mutant)

      expected = expected_body(mutant)
      return "mutation site is outside the executed method body" unless expected

      source = Mutant::Activator.activation_source_for(mutant)
      return "activation source could not be built" unless source

      syntax_violation(source) || structure_violation(mutant, expected, source)
    rescue StandardError => e
      "fidelity could not be verified (#{e.class}: #{e.message})"
    end

    private

    def checkable?(mutant)
      return false unless mutant.original_node

      subject = mutant.subject
      !subject.method_name.nil? && !subject.ast_node.nil?
    end

    def syntax_violation(source)
      error = Prism.parse(source).errors.first
      "activation source is not valid Ruby: #{error.message}" if error
    end

    def structure_violation(mutant, expected, source)
      tree = SourceParser.parse(source, path: Mutant::Activator::EVAL_FILE)
      actual = normalize(activated_body(tree, mutant.subject.method_name))
      expected = normalize(expected)
      return "activated code differs from the reported mutation" unless actual == expected

      form_violation(expected, actual, original_index(mutant), format_index(source))
    end

    # The mutated node takes the original node's location, so the syntax-form
    # check can compare the mutation site itself; operators often build the
    # replacement without one.
    def expected_body(mutant)
      original = mutant.original_node
      replacement = mutant.mutated_node&.updated(nil, nil, location: original.location)
      replaced, found = substitute(method_body(mutant.subject.ast_node), original, replacement)
      replaced if found
    end

    def method_body(node)
      case node.type
      when :defs then node.children[3]
      when :def, :block then node.children[2]
      end
    end

    def substitute(node, target, replacement)
      return [replacement, true] if node.equal?(target)
      return [node, false] unless node.is_a?(Parser::AST::Node)

      found = false
      children = node.children.map do |child|
        child, child_found = substitute(child, target, replacement)
        found ||= child_found
        child
      end
      [found ? node.updated(nil, children) : node, found]
    end

    def activated_body(tree, method_name)
      definition = find_node(tree) do |node|
        node.type == :block && define_method_call?(node.children[0], method_name)
      end
      definition&.children&.at(2)
    end

    def define_method_call?(call, method_name)
      call.type == :send && call.children[0].nil? && call.children[1] == :define_method &&
        call.children[2]&.type == :sym && call.children[2].children[0] == method_name.to_sym
    end

    def find_node(node, &)
      return unless node.is_a?(Parser::AST::Node)
      return node if yield(node)

      node.children.each do |child|
        found = find_node(child, &)
        return found if found
      end
      nil
    end

    def normalize(node)
      return node unless node.is_a?(Parser::AST::Node)
      return node.updated(:str, [literal_text(node)]) if literal_dstr?(node)
      return node.updated(nil, [File.expand_path(node.children[0])]) if file_keyword?(node)

      node.updated(nil, normalized_children(node))
    end

    def normalized_children(node)
      children = node.children.map { |child| normalize(child) }
      node.type == :begin ? children.flat_map { |child| statements(child) } : children
    end

    # A statement sequence spliced into another one parses as one flat
    # sequence.
    def statements(node)
      node.is_a?(Parser::AST::Node) && node.type == :begin ? node.children : [node]
    end

    def file_keyword?(node)
      node.type == :str && node.location&.expression&.source == "__FILE__"
    end

    # An interpolation-free heredoc parses into a +dstr+ of line segments.
    def literal_dstr?(node)
      node.type == :dstr && node.children.all? { |child| child.type == :str || literal_dstr?(child) }
    end

    def literal_text(node)
      return node.children[0] if node.type == :str

      node.children.map { |child| literal_text(child) }.join
    end

    def form_violation(expected, actual, original_forms, actual_forms)
      each_pair(expected, actual) do |expected_node, actual_node|
        before = forms_at(original_forms, expected_node)
        next unless before

        after = forms_at(actual_forms, actual_node) || []
        changed = (before - after) + (after - before)
        return form_message(changed.first, expected_node) unless changed.empty?
      end
      nil
    end

    def form_message(type, node)
      "activated code changes the syntax form of `#{type}` at line #{node.location.expression.line}"
    end

    def each_pair(expected, actual, &)
      return unless expected.is_a?(Parser::AST::Node)

      yield expected, actual
      expected.children.zip(actual.children).each do |expected_child, actual_child|
        each_pair(expected_child, actual_child, &)
      end
    end

    def forms_at(index, node)
      range = node.location&.expression
      return unless range

      index.fetch([range.begin_pos, range.end_pos], [])
    end

    def original_index(mutant)
      buffer = mutant.subject.ast_node.location.expression.source_buffer
      @format_index_cache[buffer] ||= format_index(buffer.source)
    end

    def format_index(source)
      index = Hash.new { |hash, key| hash[key] = [] }
      collect_forms(modern_parse(source), index)
      index
    end

    def collect_forms(node, index)
      return unless node.is_a?(Parser::AST::Node)

      range = node.location&.expression
      index[[range.begin_pos, range.end_pos]] << node.type if range && FORMAT_TYPES.include?(node.type)
      node.children.each { |child| collect_forms(child, index) }
    end

    def modern_parse(source)
      buffer = Parser::Source::Buffer.new("(fidelity)")
      buffer.source = source
      Prism::Translation::ParserCurrent.new(ModernBuilder.new).parse(buffer)
    end
  end
end
