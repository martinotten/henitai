# frozen_string_literal: true

require "digest"

module Henitai
  # Samples mutants deterministically, stratified by operator within each subject.
  #
  # Per subject, the sample size is ceil(size * ratio), at least one and at most
  # size. Mutants are grouped into strata by operator. Each stratum is ordered by
  # a seeded SHA256 key derived from the mutant's stable id, so a mutant's rank
  # does not depend on other mutants. Strata are then visited round-robin, which
  # spreads the sample across operators and positions. Kept mutants are returned
  # in their input order.
  class SamplingStrategy
    DEFAULT_SEED = 0

    def sample(mutants, ratio:, strategy: :stratified, seed: DEFAULT_SEED)
      strategy = strategy.to_sym if strategy.respond_to?(:to_sym)

      case strategy
      when :stratified
        stratified_sample(Array(mutants), ratio:, seed:)
      else
        raise ArgumentError, "Unsupported sampling strategy: #{strategy}"
      end
    end

    private

    def stratified_sample(mutants, ratio:, seed:)
      return [] if ratio.to_f <= 0.0

      kept = {}.compare_by_identity
      mutants.group_by { |mutant| mutant.subject.expression }.each_value do |group|
        select_within_subject(group, ratio:, seed:).each { |mutant| kept[mutant] = true }
      end
      mutants.select { |mutant| kept.key?(mutant) }
    end

    def select_within_subject(group, ratio:, seed:)
      strata = group.group_by { |mutant| mutant.operator.to_s }.sort.map do |_operator, members|
        members.sort_by { |mutant| sort_key(mutant, seed) }
      end

      round_robin(strata, sample_count(group.size, ratio))
    end

    def round_robin(strata, count)
      depth = strata.map(&:size).max || 0

      (0...depth).flat_map { |index| strata.filter_map { |stratum| stratum[index] } }.first(count)
    end

    def sort_key(mutant, seed)
      Digest::SHA256.hexdigest("#{seed}\0#{mutant.stable_id}")
    end

    def sample_count(size, ratio)
      count = (size * ratio).ceil
      count = 1 if count < 1
      [count, size].min
    end
  end
end
