# frozen_string_literal: true

module Henitai
  # Namespace for result reporters.
  #
  # Each reporter receives a Result object and writes output in its specific
  # format. Reporters are selected via `reporters:` in .henitai.yml.
  #
  # Built-in reporters:
  #   terminal  — coloured summary table to STDOUT
  #   json      — mutation-testing-report-schema JSON file
  #   html      — self-contained HTML using mutation-testing-elements web component
  #   dashboard — POST to Stryker Dashboard REST API
  module Reporter
    # @param names  [Array<String>] reporter names from configuration
    # @param result [Result]
    # @param config [Configuration]
    def self.run_all(names:, result:, config:)
      names.each do |name|
        reporter_class(name).new(config:).report(result)
      end
    end

    def self.reporter_class(name)
      const_get(name.capitalize)
    rescue NameError
      raise ArgumentError, "Unknown reporter: #{name}. Valid reporters: terminal, json, html, dashboard"
    end

    # Base class for all reporters.
    class Base
      def initialize(config:)
        @config = config
      end

      # @param result [Result]
      def report(result)
        raise NotImplementedError, "#{self.class}#report must be implemented"
      end

      private

      attr_reader :config
    end

    # Terminal reporter.
    class Terminal < Base
      PROGRESS_GLYPHS = {
        killed: "·",
        survived: "S",
        timeout: "T",
        ignored: "I"
      }.freeze

      def report(result)
        result.mutants.each { |mutant| progress(mutant) }
      end

      def progress(mutant)
        glyph = PROGRESS_GLYPHS[mutant.status]
        return unless glyph

        print(glyph)
        $stdout.flush
      end
    end

    # JSON reporter.
    class Json < Base
      def report(result)
        raise NotImplementedError
      end
    end

    # HTML reporter.
    class Html < Base
      def report(result)
        raise NotImplementedError
      end
    end

    # Dashboard reporter.
    class Dashboard < Base
      def report(result)
        raise NotImplementedError
      end
    end
  end
end
