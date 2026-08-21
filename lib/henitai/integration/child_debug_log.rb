# frozen_string_literal: true

require_relative "loaded_features"

module Henitai
  module Integration
    # Diagnostics writer for the mutant child process, gated on
    # `HENITAI_DEBUG_CHILD=1`.
    #
    # Every method gates on {#enabled?} itself rather than trusting call sites,
    # so no unguarded caller can leak debug lines into every child log by
    # default.
    class ChildDebugLog
      PREFIX = "[henitai-debug-child]"

      def initialize(io: nil, loaded_features: LoadedFeatures.new)
        @io = io
        @loaded_features = loaded_features
      end

      def enabled? = ENV["HENITAI_DEBUG_CHILD"] == "1"

      def write(message)
        return unless enabled?

        io.puts(message)
        io.flush
      end

      def rspec_trace(test_files:, rspec_options:, rspec_argv:)
        return unless enabled?

        write(
          "#{PREFIX} cwd=#{Dir.pwd}\n" \
          "#{PREFIX} files_exist=#{test_files.map { |file| [file, File.exist?(file)] }.inspect}\n" \
          "#{PREFIX} loaded_features_check=#{@loaded_features.map(test_files).inspect}\n" \
          "#{PREFIX} test_files=#{test_files.inspect}\n" \
          "#{PREFIX} rspec_options=#{rspec_options.inspect}\n" \
          "#{PREFIX} rspec_argv=#{rspec_argv.inspect}"
        )
      end

      def rspec_exit(status)
        write("#{PREFIX} RSpec result=#{status.inspect}")
      end

      def example_count(stage)
        return unless enabled?

        write("#{PREFIX} rspec_world_example_count_#{stage}=#{rspec_world_example_count.inspect}")
      end

      def activation_start(mutant_id)
        write("#{PREFIX} activate_start mutant=#{mutant_id}")
      end

      def activation_end(activation_result, test_files:)
        write(
          "#{PREFIX} activate_end result=#{activation_result.inspect}\n" \
          "#{PREFIX} run_tests_start test_files=#{test_files.inspect}"
        )
      end

      def mutant_meta(mutant)
        return unless enabled?

        write(
          "#{PREFIX} mutant_meta stableId=#{value_of(mutant, :stable_id)}\n" \
          "#{PREFIX} mutant_meta operator=#{value_of(mutant, :operator)}\n" \
          "#{PREFIX} mutant_meta subject=#{subject_expression_of(mutant)}\n" \
          "#{PREFIX} mutant_meta location=#{location_of(mutant)}\n"
        )
      end

      # Reports where Runner#resolve_subjects was loaded from, which is how a
      # child that activated a mutant on Henitai's own source is identified.
      def activation_check
        return unless enabled?

        location = begin
          Henitai::Runner.instance_method(:resolve_subjects).source_location&.join(":") # henitai:disable
        rescue StandardError
          nil
        end

        write("#{PREFIX} activation_check resolve_subjects_location=#{location}\n")
      end

      def timeout_signal_sent(pid)
        write("#{PREFIX} timeout_signal_sent pid=#{pid}")
      end

      def thread_dump(reason)
        return unless enabled?

        write("#{PREFIX} thread_dump reason=#{reason}")
        Thread.list.each_with_index { |thread, index| dump_thread(thread, index) }
      end

      def rspec_world_example_count
        ::RSpec.world.example_count
      rescue StandardError
        nil
      end

      private

      def dump_thread(thread, index)
        write(
          "#{PREFIX} thread index=#{index} id=#{thread.object_id} " \
          "status=#{thread.status.inspect}"
        )
        Array(thread.backtrace).each { |line| write("#{PREFIX}   #{line}") }
      end

      def value_of(mutant, name) = mutant.respond_to?(name) ? mutant.public_send(name) : nil

      # Deliberately `.inspect` inside the ternary, not on the result: a mutant
      # without #location must render as empty, not as the string "nil".
      def location_of(mutant) = mutant.respond_to?(:location) ? mutant.location.inspect : nil

      def subject_expression_of(mutant)
        return nil unless mutant.respond_to?(:subject) && mutant.subject.respond_to?(:expression)

        mutant.subject.expression
      end

      # Resolved per call, never memoized: ScenarioLogSupport#capture_child_output
      # reassigns $stdout inside the child *after* this object is built, so a
      # captured-at-construction stream would send every debug line to the
      # parent's terminal instead of the child's log file.
      def io = @io || $stdout
    end
  end
end
