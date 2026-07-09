# frozen_string_literal: true

module Henitai
  # Fans a single #progress callback out to several observers so the execution
  # engines keep exactly one progress hook. Used to run the terminal reporter
  # and the checkpoint writer side by side.
  class CompositeProgressReporter
    # Assembles the active progress reporters for a run: the terminal reporter
    # when terminal output is on, and the checkpoint writer when enabled and a
    # file report (json/html) is configured. Returns a single reporter when only
    # one is active, the composite when several are, or nil when none are.
    def self.for(config:, source_provider:, full_run:)
      active = [terminal_for(config), checkpoint_for(config, source_provider, full_run)].compact
      return active.first if active.one?

      active.empty? ? nil : new(active)
    end

    def self.terminal_for(config)
      Reporter::Terminal.new(config:) if reporter?(config, "terminal")
    end

    def self.checkpoint_for(config, source_provider, full_run)
      return unless config.respond_to?(:checkpoint_enabled) && config.checkpoint_enabled
      return unless reporter?(config, "json") || reporter?(config, "html")

      CheckpointReporter.new(config:, source_provider:, authoritative: full_run)
    end

    def self.reporter?(config, name)
      Array(config.reporters).map(&:to_s).include?(name)
    end

    def initialize(reporters)
      @reporters = reporters.compact
    end

    def progress(mutant, scenario_result: nil)
      @reporters.each { |reporter| reporter.progress(mutant, scenario_result:) }
    end
  end
end
