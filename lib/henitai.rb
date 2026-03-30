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

  autoload :Configuration,  "henitai/configuration"
  autoload :Subject,         "henitai/subject"
  autoload :Mutant,          "henitai/mutant"
  autoload :Operator,        "henitai/operator"
  autoload :Runner,          "henitai/runner"
  autoload :Reporter,        "henitai/reporter"
  autoload :Integration,     "henitai/integration"
  autoload :Result,          "henitai/result"
  autoload :CLI,             "henitai/cli"
end
