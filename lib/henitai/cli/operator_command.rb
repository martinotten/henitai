# frozen_string_literal: true

module Henitai
  class CLI
    # Implements `henitai operator`: lists the built-in operators with their
    # human-readable descriptions and examples. Mixed into {CLI}.
    module OperatorCommand
      OPERATOR_METADATA = {
        "ArithmeticOperator" => ["Arithmetic operators", "a + b -> a - b"],
        "EqualityOperator" => ["Comparison operators", "a == b -> a != b"],
        "LogicalOperator" => ["Boolean operators", "a && b -> a || b"],
        "BooleanLiteral" => ["Boolean literals", "true -> false"],
        "ConditionalExpression" => ["Conditional branches", "if cond then ... end"],
        "StringLiteral" => ["String literals", '"foo" -> ""'],
        "ReturnValue" => ["Return expressions", "return x -> return nil"],
        "ArrayDeclaration" => ["Array literals", "[1, 2] -> []"],
        "HashLiteral" => ["Hash literals", "{ a: 1 } -> {}"],
        "RangeLiteral" => ["Range literals", "1..5 -> 1...5"],
        "SafeNavigation" => ["Safe navigation", "user&.name -> user.name"],
        "PatternMatch" => ["Pattern matching", "in { x: Integer } -> in { x: String }"],
        "BlockStatement" => ["Block statements", "{ do_work } -> {}"],
        "MethodExpression" => ["Method calls", "call_service -> nil"],
        "AssignmentExpression" => ["Assignment expressions", "x += 1 -> x -= 1"],
        "MethodChainUnwrap" => ["Method chain unwrap", "a.b.c -> a.b"],
        "RegexMutator" => ["Regex literals", "/foo+/ -> /foo*/"],
        "UnaryOperator" => ["Unary operators", "-x -> x"],
        "UpdateOperator" => ["Compound assignment", "x += 1 -> x -= 1"]
      }.freeze

      private

      def operator_command
        subcommand = @argv.shift
        case subcommand
        when "list" then puts operator_list_text
        when nil, "-h", "--help" then puts operator_help_text
        else
          warn "Unknown operator command: #{subcommand}"
          warn operator_help_text
          exit 1
        end
      rescue ArgumentError => e
        warn e.message
        exit 1
      end

      def operator_help_text
        <<~HELP
          Hen'i-tai operator commands

          Usage:
            henitai operator list

          Run `henitai operator list` to see all built-in operators.
        HELP
      end

      def operator_list_text
        validate_operator_metadata!
        sections = [
          operator_list_section("Light set", Operator::LIGHT_SET),
          operator_list_section("Full set", Operator::FULL_SET)
        ]

        ["Available operators", *sections].join("\n")
      end

      def operator_list_section(title, names)
        rows = names.map { |name| operator_description_row(name) }
        ([title] + rows).join("\n")
      end

      def operator_description_row(name)
        description, example = operator_metadata[name] || fallback_operator_metadata

        format("- %<name>s: %<description>s (%<example>s)", name:, description:, example:)
      end

      def operator_metadata
        OPERATOR_METADATA
      end

      def fallback_operator_metadata
        ["No metadata available", "n/a"]
      end

      def validate_operator_metadata!
        missing = Operator::FULL_SET - operator_metadata.keys
        return if missing.empty?

        raise ArgumentError, "Missing operator metadata for: #{missing.join(', ')}"
      end
    end
  end
end
