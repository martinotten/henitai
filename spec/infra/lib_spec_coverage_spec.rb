# frozen_string_literal: true

require "spec_helper"

# Scoped to top-level lib/henitai/*.rb, not the full **/*.rb tree: files
# under lib/henitai/cli/, configuration_validator/, integration/,
# mutant_history_store/, reporter/, and slot_scheduler/ are private
# decomposition components exercised behaviorally through their facade's
# spec (e.g. cli_spec.rb drives Cli::RunCommand without naming it), not via
# a same-named spec file. Guarding those would produce false positives, not
# real gaps. lib/henitai/operators/ and lib/henitai/mutant/ do follow a
# strict 1:1 file<->spec convention already, so this guard doesn't need to
# police them separately.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Lib spec coverage" do
  let(:root) { File.expand_path("../..", __dir__) }

  # Top-level files with an accepted, documented reason for having no
  # matching spec/henitai/<name>_spec.rb.
  let(:allowlist) do
    {
      "version.rb" =>
        "single VERSION constant; a spec would be tautological " \
        "(see docs/backlog/2026-06-16-review-test-overmocking-and-gaps.md)",
      "integration.rb" => "facade tested via spec/henitai/integration/ and callers",
      "survivor_rerun_strategy.rb" => "instantiated and exercised directly in runner_spec.rb"
    }
  end

  def matching_spec_exists?(name)
    stem = name.delete_suffix(".rb")
    patterns = ["#{stem}_spec.rb", "#{stem}_process_spec.rb"]
    patterns.any? { |pattern| File.exist?(File.join(root, "spec/henitai", pattern)) }
  end

  it "gives every top-level lib file a matching spec file" do
    lib_files = Dir.glob(File.join(root, "lib/henitai/*.rb")).map { |path| File.basename(path) }
    checked = lib_files.reject { |name| allowlist.key?(name) }

    missing = checked.reject { |name| matching_spec_exists?(name) }

    expect(missing).to be_empty
  end

  it "keeps the allowlist free of files that already have a spec" do
    stale = allowlist.keys.select { |name| matching_spec_exists?(name) }

    expect(stale).to be_empty
  end
end
# rubocop:enable RSpec/DescribeClass
