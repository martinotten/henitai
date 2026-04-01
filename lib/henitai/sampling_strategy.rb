# frozen_string_literal: true

module Henitai
  # Samples mutants in a strategy-aware, deterministic way.
  class SamplingStrategy
    def sample(mutants, ratio:, strategy: :stratified)
      strategy = strategy.to_sym if strategy.respond_to?(:to_sym)

      case strategy
      when :stratified
        stratified_sample(Array(mutants), ratio:)
      else
        raise ArgumentError, "Unsupported sampling strategy: #{strategy}"
      end
    end

    private

    def stratified_sample(mutants, ratio:)
      return [] if ratio.to_f <= 0.0

      mutants.group_by { |mutant| mutant.subject.expression }.flat_map do |_subject, group|
        group.take(sample_count(group.size, ratio))
      end
    end

    def sample_count(size, ratio)
      count = (size * ratio).ceil
      count = 1 if count < 1
      [count, size].min
    end
  end
end
