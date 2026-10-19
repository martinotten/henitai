# frozen_string_literal: true

module Henitai
  module Integration
    # Finds the test file a Minitest result belongs to.
    #
    # `Result#source_location` is where the test method is defined. For tests
    # inherited from a base class or an included module that is a shared file,
    # not the file of the test class that ran. The file that defines the
    # result's class is used instead; the method location is the fallback for
    # classes that cannot be resolved (anonymous or removed).
    module MinitestResultFile
      module_function

      # Records the result's outcome; a failure with no usable file is
      # recorded as unattributed rather than dropped.
      def record(outcomes, result)
        failed = !result.passed? && !result.skipped?
        file = self.for(result)
        if file
          outcomes.record(file, failed:)
        elsif failed
          outcomes.record_unattributed_failure
        end
      end

      # @return [String, nil] the test file, or nil when none can be found
      def for(result)
        usable(class_file(result)) || usable(method_file(result))
      end

      def class_file(result)
        Object.const_source_location(result.klass.to_s)&.first
      rescue NameError
        nil
      end

      def method_file(result)
        result.source_location&.first
      end

      # Minitest reports no location for some results and "unknown" for others.
      def usable(file)
        file if file.is_a?(String) && !file.empty? && file != "unknown" && file != "(eval)"
      end
    end
  end
end
