# frozen_string_literal: true

module Henitai
  module Integration
    # Shared debug helpers for child-run diagnostics.
    # Debug helpers are intentionally grouped here so the child-run diagnostics
    # stay isolated from the main integration flow.
    module ChildDebugSupport
      private

      def debug_child? = ENV["HENITAI_DEBUG_CHILD"] == "1"

      def debug_child_puts(message)
        return unless debug_child?

        $stdout.puts(message)
        $stdout.flush
      end

      def debug_child_rspec_trace(test_files:, rspec_options:, rspec_argv:)
        return unless debug_child?

        files_exist = test_files.map { |f| [f, File.exist?(f)] }.inspect
        loaded_features = loaded_feature_map(test_files).inspect # steep:ignore Ruby::NoMethod

        debug_child_puts(
          "[henitai-debug-child] cwd=#{Dir.pwd}\n" \
          "[henitai-debug-child] files_exist=#{files_exist}\n" \
          "[henitai-debug-child] loaded_features_check=#{loaded_features}\n" \
          "[henitai-debug-child] test_files=#{test_files.inspect}\n" \
          "[henitai-debug-child] rspec_options=#{rspec_options.inspect}\n" \
          "[henitai-debug-child] rspec_argv=#{rspec_argv.inspect}"
        )
      end

      def debug_child_rspec_exit(status)
        return unless debug_child?

        debug_child_puts("[henitai-debug-child] RSpec result=#{status.inspect}")
      end

      def debug_child_example_count(stage) # steep:ignore Ruby::UndeclaredMethodDefinition
        return unless debug_child?

        count = rspec_world_example_count
        debug_child_puts(
          "[henitai-debug-child] rspec_world_example_count_#{stage}=#{count.inspect}"
        )
      end

      def debug_child_activation_start(mutant_id)
        return unless debug_child?

        debug_child_puts("[henitai-debug-child] activate_start mutant=#{mutant_id}")
      end

      def debug_child_activation_end(activation_result, test_files:)
        return unless debug_child?

        debug_child_puts(
          "[henitai-debug-child] activate_end result=#{activation_result.inspect}\n" \
          "[henitai-debug-child] run_tests_start test_files=#{test_files.inspect}"
        )
      end

      def debug_child_mutant_meta(mutant)
        stable_id = mutant.respond_to?(:stable_id) ? mutant.stable_id : nil
        operator = mutant.respond_to?(:operator) ? mutant.operator : nil
        has_subject_expression =
          mutant.respond_to?(:subject) && mutant.subject.respond_to?(:expression)
        subject_expression = has_subject_expression ? mutant.subject.expression : nil
        location = mutant.respond_to?(:location) ? mutant.location.inspect : nil

        debug_child_puts(
          "[henitai-debug-child] mutant_meta stableId=#{stable_id}\n" \
          "[henitai-debug-child] mutant_meta operator=#{operator}\n" \
          "[henitai-debug-child] mutant_meta subject=#{subject_expression}\n" \
          "[henitai-debug-child] mutant_meta location=#{location}\n"
        )
      end

      def debug_child_activation_check
        location = begin
          Henitai::Runner.instance_method(:resolve_subjects).source_location&.join(":")
        rescue StandardError
          nil
        end

        debug_child_puts(
          "[henitai-debug-child] activation_check resolve_subjects_location=#{location}\n"
        )
      end

      def loaded_feature_map(test_files) = test_files.map { |file| [file, loaded_feature?(file)] } # steep:ignore Ruby::UndeclaredMethodDefinition

      def loaded_feature?(file) # steep:ignore Ruby::UndeclaredMethodDefinition
        expanded = File.expand_path(file)
        candidates = [expanded, "#{expanded}.rb", file, "#{file}.rb"].uniq
        $LOADED_FEATURES.any? do |feature|
          normalized = begin
            File.expand_path(feature)
          rescue StandardError
            feature
          end
          candidates.include?(feature) || candidates.include?(normalized)
        end
      end

      def rspec_world_example_count # steep:ignore Ruby::UndeclaredMethodDefinition
        world = ::RSpec.__send__(:world)
        world.example_count
      rescue StandardError
        nil
      end
    end
  end
end
