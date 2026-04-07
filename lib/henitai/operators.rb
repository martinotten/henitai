# frozen_string_literal: true

module Henitai
  # Namespace for concrete mutation operators.
  #
  # Concrete operator classes are autoloaded so the registry stays lightweight
  # until a specific operator is referenced.
  module Operators
    autoload :ArithmeticOperator, "henitai/operators/arithmetic_operator"
    autoload :EqualityOperator, "henitai/operators/equality_operator"
    autoload :LogicalOperator, "henitai/operators/logical_operator"
    autoload :BooleanLiteral, "henitai/operators/boolean_literal"
    autoload :ConditionalExpression, "henitai/operators/conditional_expression"
    autoload :StringLiteral, "henitai/operators/string_literal"
    autoload :ReturnValue, "henitai/operators/return_value"
    autoload :ArrayDeclaration, "henitai/operators/array_declaration"
    autoload :HashLiteral, "henitai/operators/hash_literal"
    autoload :RangeLiteral, "henitai/operators/range_literal"
    autoload :SafeNavigation, "henitai/operators/safe_navigation"
    autoload :PatternMatch, "henitai/operators/pattern_match"
    autoload :BlockStatement, "henitai/operators/block_statement"
    autoload :MethodExpression, "henitai/operators/method_expression"
    autoload :AssignmentExpression, "henitai/operators/assignment_expression"
    autoload :MethodChainUnwrap,    "henitai/operators/method_chain_unwrap"
    autoload :RegexMutator,         "henitai/operators/regex_mutator"
    autoload :UnaryOperator,        "henitai/operators/unary_operator"
    autoload :UpdateOperator,       "henitai/operators/update_operator"
  end
end
