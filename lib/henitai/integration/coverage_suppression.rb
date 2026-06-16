# frozen_string_literal: true

module Henitai
  module Integration
    # Prepended onto SimpleCov's singleton class to turn start into a no-op
    # during mutant child runs. Using prepend avoids "method redefined" warnings.
    module SimpleCovStartSuppressor
      def start(*_args) = nil
    end

    # Prepended onto the coverage gem's Coverage singleton to turn start
    # into a no-op during mutant child runs.
    module CoverageStartSuppressor
      def start(*_args) = nil
    end

    # Suppresses expensive and irrelevant coverage startup/teardown during
    # mutant child runs. Coverage artifacts are only required during the
    # dedicated bootstrap phase.
    module CoverageRuntimeSuppressors
      def self.suppress_simplecov!
        require "simplecov"
        sc = Object.const_get(:SimpleCov) # steep:ignore Ruby::UnknownConstant
        sc.external_at_exit = true if sc.respond_to?(:external_at_exit=)
        return if sc.singleton_class.ancestors.include?(SimpleCovStartSuppressor)

        sc.singleton_class.prepend(SimpleCovStartSuppressor)
      rescue LoadError, NameError
        nil
      end

      def self.suppress_coverage!
        require "coverage"
        cov = Object.const_get(:Coverage) # steep:ignore Ruby::UnknownConstant
        return if cov.singleton_class.ancestors.include?(CoverageStartSuppressor)

        cov.singleton_class.prepend(CoverageStartSuppressor)
      rescue LoadError, NameError
        nil
      end
    end
  end
end
