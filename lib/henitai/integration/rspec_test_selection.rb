# frozen_string_literal: true

module Henitai
  module Integration
    # Spec-file discovery and subject-to-spec matching for the RSpec
    # integration. Selection uses longest-prefix matching against the subject
    # expression and namespace, with a transitive require-based fallback.
    module RspecTestSelection
      REQUIRE_DIRECTIVE_PATTERN = /
        \A\s*
        (require|require_relative)
        \s*
        (?:\(\s*)?
        ["']([^"']+)["']
        \s*\)?
      /x

      def select_tests(subject)
        matches = spec_files.select do |path|
          content = File.read(path)
          selection_patterns(subject).any? { |pattern| content.include?(pattern) }
        rescue StandardError
          false
        end

        return matches unless matches.empty?

        fallback_spec_files(subject)
      end

      def spec_files
        @spec_files ||= begin
          paths = Dir.glob("spec/**/*_spec.rb")
          paths - excluded_spec_files
        end
      end

      def fallback_spec_files(subject)
        return [] unless subject.source_file

        matches = spec_files.select do |path|
          requires_source_file_transitively?(path, subject.source_file)
        rescue StandardError
          false
        end

        matches.empty? ? spec_files : matches
      end

      def excluded_spec_files
        @excluded_spec_files ||= rspec_exclude_patterns.flat_map { |pattern| Dir.glob(pattern) }.uniq
      end

      def rspec_exclude_patterns
        rspec_config_lines.filter_map do |line|
          line[/\A--exclude-pattern\s+(.+)\z/, 1]
        end
      end

      def rspec_config_lines
        return [] unless File.exist?(rspec_config_path)

        File.readlines(rspec_config_path, chomp: true).map(&:strip)
      end

      def rspec_config_path
        ".rspec"
      end

      def selection_patterns(subject)
        [
          subject.expression,
          subject.namespace
        ].compact.uniq.sort_by(&:length).reverse
      end

      def requires_source_file?(spec_file, source_file)
        content = File.read(spec_file)
        basename = File.basename(source_file, ".rb")
        content.include?(basename) || content.include?(source_file)
      end

      def requires_source_file_transitively?(spec_file, source_file, visited = [])
        normalized_spec_file = File.expand_path(spec_file)
        return false if visited.include?(normalized_spec_file)

        visited << normalized_spec_file
        return true if requires_source_file?(spec_file, source_file)

        required_files(spec_file).any? do |required_file|
          requires_source_file_transitively?(required_file, source_file, visited)
        end
      end

      def required_files(spec_file)
        File.read(spec_file).lines.filter_map do |line|
          match = line.match(REQUIRE_DIRECTIVE_PATTERN)
          next unless match

          resolve_required_file(spec_file, match[1].to_s, match[2].to_s)
        end
      end

      def resolve_required_file(spec_file, method_name, required_path)
        candidates =
          if method_name == "require_relative"
            relative_candidates(spec_file, required_path)
          else
            require_candidates(spec_file, required_path)
          end

        candidates.find { |candidate| File.file?(candidate) }
      end

      def relative_candidates(spec_file, required_path)
        expand_candidates(File.dirname(spec_file), required_path)
      end

      def require_candidates(spec_file, required_path)
        ([File.dirname(spec_file), Dir.pwd] + $LOAD_PATH).flat_map do |base_path|
          expand_candidates(base_path, required_path)
        end
      end

      def expand_candidates(base_path, required_path)
        [
          File.expand_path(required_path, base_path),
          File.expand_path("#{required_path}.rb", base_path)
        ].uniq
      end
    end
  end
end
