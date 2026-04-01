# frozen_string_literal: true

require_relative "henitai/version"

# Hen'i-tai (変異体) — Mutation testing for Ruby
#
# Usage:
#   henitai run --use rspec 'MyNamespace*'
#   henitai run --since HEAD~1 'MyClass#my_method'
#
module Henitai
  # Raised when the framework encounters a configuration error
  class ConfigurationError < StandardError; end

  # Raised when a subject expression cannot be resolved
  class SubjectNotFound < StandardError; end

  autoload :Configuration, "henitai/configuration"
  autoload :Subject, "henitai/subject"
  autoload :Mutant, "henitai/mutant"
  autoload :Operator, "henitai/operator"
  autoload :Operators, "henitai/operators"
  autoload :SourceParser, "henitai/source_parser"
  autoload :SubjectResolver, "henitai/subject_resolver"
  autoload :GitDiffAnalyzer, "henitai/git_diff_analyzer"
  autoload :GitDiffError, "henitai/git_diff_analyzer"
  autoload :MutantGenerator, "henitai/mutant_generator"
  autoload :AridNodeFilter, "henitai/arid_node_filter"
  autoload :StaticFilter, "henitai/static_filter"
  autoload :StillbornFilter, "henitai/stillborn_filter"
  autoload :SyntaxValidator, "henitai/syntax_validator"
  autoload :SamplingStrategy, "henitai/sampling_strategy"
  autoload :Runner, "henitai/runner"
  autoload :Reporter, "henitai/reporter"
  autoload :Integration, "henitai/integration"
  autoload :Result, "henitai/result"
  autoload :CLI, "henitai/cli"
end
