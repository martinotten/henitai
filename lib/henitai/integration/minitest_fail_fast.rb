# frozen_string_literal: true

require "minitest"

module Henitai
  module Integration
    # Ends a mutant child's Minitest run at its first failing test: one
    # failure already kills the mutant. Minitest has no fail-fast of its own;
    # once stopped, every test class that has not started yet reports no test
    # methods, so Minitest skips it. The class running at the failure still
    # finishes. Armed only around the child's Minitest.run, never for the
    # baseline suite.
    module MinitestFailFast
      # Prepended to Minitest::Test's singleton class; Minitest 5 and 6 both
      # ask a test class for its runnable methods when it starts.
      module StoppableSuites
        def runnable_methods
          MinitestFailFast.stopped? ? [] : super
        end
      end

      class << self
        def arm!
          suites = ::Minitest::Test.singleton_class
          suites.prepend(StoppableSuites) unless suites.include?(StoppableSuites)
          @state = :armed
        end

        def disarm!
          @state = nil
        end

        def stop!
          @state = :stopped if @state
        end

        def armed? = !@state.nil?

        def stopped? = @state == :stopped
      end
    end
  end
end
