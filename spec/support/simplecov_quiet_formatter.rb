# frozen_string_literal: true

require "simplecov-html"
require "stringio"

module SimpleCov
  module Formatter
    class QuietHTMLFormatter
      def format(result)
        with_suppressed_stdout do
          HTMLFormatter.new.format(result)
        end
      end

      private

      def with_suppressed_stdout
        original_stdout = $stdout
        sink = StringIO.new
        $stdout = sink
        yield
      ensure
        $stdout = original_stdout if original_stdout
      end
    end
  end
end
