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
  #
  # A violation is a harness defect, not a test verdict: the mutant must not
  # run, and the reason must be reported.
  class FidelityCheck
    # @return [String, nil] the reason the mutant is unfaithful, or nil
    def violation(mutant)
      return unless checkable?(mutant)

      activation = Mutant::Activator.activation_for(mutant)
      return "activation source could not be built" unless activation

      whole_def = activation.mode == :toplevel
      expected = expected_tree(mutant, whole_def)
      return "mutation site is outside the executed method body" unless expected

      syntax_violation(activation.source) || structure_violation(mutant, expected, activation, whole_def)
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

    def structure_violation(mutant, expected, activation, whole_def)
      source = activation.source
      tree = SourceParser.parse(source, path: activation.file || Mutant::Activator::EVAL_FILE)
      actual = normalize(activated_tree(tree, mutant.subject.method_name, whole_def))
      expected = normalize(expected)
      "activated code differs from the reported mutation" unless actual == expected
    end

    # A re-evaluated def (ADR-13) is compared as a whole, parameters
    # included; the define_method fallback only by body.
    def expected_tree(mutant, whole_def)
      definition = mutant.subject.ast_node
      scope = whole_def ? definition : method_body(definition)
      replaced, found = substitute(scope, mutant.original_node, mutant.mutated_node)
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

    # The method as activated: a re-evaluated +def+ (ADR-13) or the
    # +define_method+ block of the fallback.
    def activated_tree(tree, method_name, whole_def)
      name = method_name.to_sym
      definition = find_node(tree) do |node|
        activated_def?(node, name) || (node.type == :block && define_method_call?(node.children[0], name))
      end
      whole_def ? definition : definition && method_body(definition)
    end

    def activated_def?(node, name)
      (node.type == :def && node.children[0] == name) || (node.type == :defs && node.children[1] == name)
    end

    def define_method_call?(call, method_name)
      call.type == :send && call.children[0].nil? && call.children[1] == :define_method &&
        call.children[2]&.type == :sym && call.children[2].children[0] == method_name
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

    # `foo(a, )` -- left behind when all keyword arguments are removed --
    # calls `foo(a)`, so an empty kwargs node is no argument at all.
    def normalized_children(node)
      children = node.children.map { |child| normalize(child) }.reject { |child| empty_kwargs?(child) }
      node.type == :begin ? children.flat_map { |child| statements(child) } : children
    end

    def empty_kwargs?(node)
      node.is_a?(Parser::AST::Node) && node.type == :kwargs && node.children.empty?
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
  end
end
