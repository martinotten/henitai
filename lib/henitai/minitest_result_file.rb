# frozen_string_literal: true

module Henitai
  # Finds the test file a Minitest result belongs to.
  #
  # `Result#source_location` is where the test method is defined. For tests
  # inherited from a base class or an included module that is a shared file,
  # not the file of the test class that ran, so the file that defines the
  # result's class is used for those. A method defined directly on the class
  # keeps its own file: the class may have been reopened in another test file.
  # The method location is also the fallback for classes that cannot be
  # resolved (anonymous or removed).
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
      return usable(method_file(result)) || usable(class_file(result)) if defined_on_class?(result)

      usable(class_file(result)) || usable(method_file(result))
    end

    def defined_on_class?(result)
      klass = Object.const_get(result.klass.to_s)
      klass.instance_method(result.name).owner == klass
    rescue NameError
      false
    end

    def class_file(result)
      class_file_of(result.klass.to_s)
    end

    # The file that defines the named class; nil for anonymous or unknown names.
    def class_file_of(name)
      usable(Object.const_source_location(name)&.first)
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
