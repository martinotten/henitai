# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SlotScheduler::TestFileSelection do
  def build_mutant(id = "a")
    subject = Struct.new(:expression).new("Foo##{id}")
    Struct.new(:id, :subject).new(id, subject)
  end

  def build_selection(options, integration: nil)
    described_class.new(options: options, integration: integration)
  end

  describe "#for" do
    it "uses the test_file_resolver option when present, passing it the mutant" do
      mutant = build_mutant
      resolver = ->(candidate) { candidate == mutant ? %w[resolved_spec.rb] : [] }
      selection = build_selection({ test_file_resolver: resolver, test_files: %w[ignored_spec.rb] })

      expect(selection.for(mutant)).to eq(%w[resolved_spec.rb])
    end

    it "falls back to the static test_files option when no resolver is set" do
      selection = build_selection({ test_files: %w[static_spec.rb] })

      expect(selection.for(build_mutant)).to eq(%w[static_spec.rb])
    end

    it "falls back to integration.select_tests when neither option is set" do
      mutant = build_mutant
      integration = instance_double(Henitai::Integration::Rspec)
      allow(integration).to receive(:select_tests).with(mutant.subject).and_return(%w[selected_spec.rb])
      selection = build_selection({}, integration: integration)

      expect(selection.for(mutant)).to eq(%w[selected_spec.rb])
    end

    # Precedence is by key presence, not truthiness. A resolver that answers
    # "no tests cover this" must not be overridden by a static list, and must
    # not fall through to the integration either.
    it "honours a resolver that returns an empty list rather than falling through" do
      integration = instance_double(Henitai::Integration::Rspec)
      selection = build_selection(
        { test_file_resolver: ->(_) { [] }, test_files: %w[fallback_spec.rb] },
        integration: integration
      )

      expect(selection.for(build_mutant)).to eq([])
    end

    it "honours an explicitly empty test_files list rather than asking the integration" do
      integration = instance_double(Henitai::Integration::Rspec)
      selection = build_selection({ test_files: [] }, integration: integration)

      expect(selection.for(build_mutant)).to eq([])
    end
  end

  describe "#resolved_empty?" do
    it "is true when a resolver is configured and came back empty" do
      selection = build_selection({ test_file_resolver: ->(_) { [] } })

      expect(selection.resolved_empty?([])).to be(true)
    end

    it "is false when a resolver is configured but found tests" do
      selection = build_selection({ test_file_resolver: ->(_) { %w[a_spec.rb] } })

      expect(selection.resolved_empty?(%w[a_spec.rb])).to be(false)
    end

    # A fixed empty list is a deliberate "run nothing", not an absence of
    # coverage — reporting :no_coverage for it would misattribute the verdict.
    it "is false for an empty static test_files list, which is not a coverage gap" do
      selection = build_selection({ test_files: [] })

      expect(selection.resolved_empty?([])).to be(false)
    end

    it "is false when no selection option is configured at all" do
      selection = build_selection({})

      expect(selection.resolved_empty?([])).to be(false)
    end
  end
end
