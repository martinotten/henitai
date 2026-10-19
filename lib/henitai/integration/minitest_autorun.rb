# frozen_string_literal: true

module Henitai
  module Integration
    # Turns Minitest.autorun into a no-op, so that requiring test files never
    # registers the at_exit hook that would run the suite a second time.
    module MinitestAutorun
      SUPPRESSOR = Module.new { def autorun = nil }

      def self.suppress!
        require "minitest"
        singleton_class = ::Minitest.singleton_class
        singleton_class.prepend(SUPPRESSOR) unless singleton_class.ancestors.include?(SUPPRESSOR)
        nil
      rescue LoadError, NameError
        nil
      end
    end
  end
end
