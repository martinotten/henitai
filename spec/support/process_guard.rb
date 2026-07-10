# frozen_string_literal: true

require "open3"

module Henitai
  module SpecSupport
    # Blocks child-process launches while mutation-safe specs are running.
    module ProcessGuard
      class ForbiddenProcess < StandardError; end

      PROCESS_METHODS = %i[exec fork spawn].freeze
      KERNEL_METHODS = %i[exec fork spawn system].freeze
      OPEN3_METHODS = %i[
        capture2 capture2e capture3 pipeline pipeline_r pipeline_rw pipeline_start
        pipeline_w popen2 popen2e popen3
      ].freeze

      class << self
        def install!
          Process.singleton_class.prepend(process_methods)
          Kernel.prepend(kernel_methods)
          Kernel.singleton_class.prepend(kernel_methods)
          IO.singleton_class.prepend(io_methods)
          Open3.singleton_class.prepend(open3_methods)
        end

        def reset!
          attempts.clear
        end

        def verify!
          recorded_attempts = attempts.uniq
          reset!
          return if recorded_attempts.empty?
          return if RSpec.current_example&.exception.is_a?(ForbiddenProcess)

          attempt_list = recorded_attempts.join(", ")
          raise ForbiddenProcess, "process-free spec attempted: #{attempt_list}"
        end

        def block!(name)
          attempts << name
          raise ForbiddenProcess, "process-free spec attempted #{name}"
        end

        private

        def attempts
          @attempts ||= []
        end

        def process_methods
          @process_methods ||= guard_methods(PROCESS_METHODS, "Process")
        end

        def kernel_methods
          @kernel_methods ||= guard_methods(KERNEL_METHODS, "Kernel") do |mod|
            mod.send(:define_method, :`) { |*| ProcessGuard.block!("Kernel#`") }
            mod.send(:private, *KERNEL_METHODS, :`)
          end
        end

        def io_methods
          @io_methods ||= guard_methods([:popen], "IO")
        end

        def open3_methods
          @open3_methods ||= guard_methods(OPEN3_METHODS, "Open3")
        end

        def guard_methods(names, owner)
          Module.new do
            names.each do |name|
              define_method(name) { |*, **, &| ProcessGuard.block!("#{owner}.#{name}") }
            end
            yield self if block_given?
          end
        end
      end
    end
  end
end

if ENV["HENITAI_PROCESS_GUARD"] == "1"
  Henitai::SpecSupport::ProcessGuard.install!

  RSpec.configure do |config|
    config.before { Henitai::SpecSupport::ProcessGuard.reset! }
    config.after { Henitai::SpecSupport::ProcessGuard.verify! }
  end
end
