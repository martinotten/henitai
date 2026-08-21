# frozen_string_literal: true

require "spec_helper"

# Guards against specs coupling to private implementation details via
# `send`, `__send__`, or instance-variable pokes.
#
# This is a ratchet, not a snapshot. Every offending file carries a budget
# with a documented reason, and the budget may only ever go down: a spec
# that beats its budget fails until the budget is lowered in the same
# commit. New files may not reach private methods at all.
#
# History that motivated this guard: twelve tickets tracking `send` reach
# sat open in docs/backlog/ while eight of the named files were cleaned up
# incidentally -- and the debt regrew into three *different* files that
# nobody had ticketed (slot_scheduler/draining_spec.rb,
# equivalence_detector_spec.rb, execution_engine_spec.rb). Nothing guarded
# it, so it moved rather than shrank.
#
# RuboCop's Style/Send is deliberately not used instead: its remedy is
# renaming `send` to `public_send`, which satisfies the cop while leaving
# the coupling exactly as it was.
#
# The declared approach for paying a budget down is to extract a public
# collaborator, not to delete the examples. See
# docs/backlog/2026-07-08-review-send-integration-minitest-spec.md, where
# extracting MinitestSuiteCommand and friends took
# Henitai::Integration::Minitest from MS 72.83% to 100%. A pure
# public-API rewrite tends to lose mutation coverage, which this repo
# scores against itself.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Private method reach in specs" do
  # This file names the very idioms it searches for, so it would always
  # match itself. Rejecting the path in code is honest; an allowlist entry
  # would need a fabricated budget that means nothing.
  let(:self_path) { "spec/infra/private_method_reach_spec.rb" }

  let(:pattern) { /\.send\(|\.__send__|instance_variable_get|instance_variable_set/ }

  # path => [max_occurrences, reason]
  #
  # Seeded from this guard's own counter at the commit that introduced it.
  # Lower a number whenever you pay one down; never raise one.
  let(:budgets) do
    {
      "spec/support/process_guard.rb" => [
        2,
        "legitimate metaprogramming -- send(:define_method) and send(:private) " \
        "install the guard's own overrides; not private-API reach on a subject"
      ],
      "spec/henitai/slot_scheduler_spec.rb" => [
        21,
        "residue is the dispatch/retry/complete mechanics plus the four delegated " \
        "host readers; needs the DrainCycle/SlotSpawner/ResultDispatcher wave " \
        "(docs/backlog/2026-07-08-review-send-slot-scheduler-spec.md)"
      ],
      "spec/henitai/slot_scheduler/draining_spec.rb" => [
        14,
        "residue is the drain state machine itself, reached slot-by-slot; needs the " \
        "DrainCycle follow-up " \
        "(docs/backlog/2026-08-21-review-send-slot-scheduler-draining-spec.md)"
      ],
      "spec/henitai/runner_spec.rb" => [
        24,
        "mix of behavior helpers reachable through #run and identity assertions on " \
        "lazily-built private dependencies; needs SourceFileSelection, SubjectSelection " \
        "and RunnerDependencies (docs/backlog/2026-07-08-review-send-runner-spec.md)"
      ]
    }
  end

  let(:root) { File.expand_path("../..", __dir__) }

  # Every .rb under spec/, not just *_spec.rb -- otherwise a support file
  # becomes a convenient hiding place for the same coupling.
  def reach_counts
    Dir.glob(File.join(root, "spec/**/*.rb")).each_with_object({}) do |path, counts|
      relative = path.delete_prefix("#{root}/")
      next if relative == self_path

      count = File.read(path).scan(pattern).size
      counts[relative] = count if count.positive?
    end
  end

  it "keeps every spec's private-method reach within its documented budget" do
    over = reach_counts.filter_map do |path, actual|
      budget = budgets.dig(path, 0) || 0
      [path, { actual:, budget: }] if actual > budget
    end

    expect(over.to_h).to eq({})
  end

  it "requires a budget to be tightened once a spec beats it" do
    counts = reach_counts

    slack = budgets.filter_map do |path, (budget, _reason)|
      actual = counts.fetch(path, 0)
      [path, { actual:, budget: }] if actual < budget
    end

    expect(slack.to_h).to eq({})
  end

  it "keeps the budget list free of specs that no longer reach private methods" do
    counts = reach_counts
    stale = budgets.keys.reject { |path| counts.key?(path) }

    expect(stale).to be_empty
  end

  it "documents a reason for every budget" do
    unexplained = budgets.reject { |_path, (_budget, reason)| reason.is_a?(String) && !reason.empty? }

    expect(unexplained.keys).to be_empty
  end
end
# rubocop:enable RSpec/DescribeClass
