# frozen_string_literal: true

module Henitai
  # Applies static, pre-execution filtering to generated mutants.
  class StaticFilter
    def apply(mutants, config)
      Array(mutants).each do |mutant|
        mutant.status = :ignored if ignored?(mutant, config)
      end

      mutants
    end

    private

    def ignored?(mutant, config)
      source = source_for(mutant)
      return false unless source

      compiled_ignore_patterns(config).any? do |pattern|
        pattern.match?(source)
      end
    end

    def source_for(mutant)
      original_node = mutant.original_node
      location = original_node&.location
      expression = location&.expression
      expression&.source
    end

    def compiled_ignore_patterns(config)
      patterns = Array(config&.ignore_patterns).dup.freeze
      @compiled_ignore_patterns ||= {}
      @compiled_ignore_patterns[patterns] ||= patterns.map { |pattern| Regexp.new(pattern) }
    end
  end
end
