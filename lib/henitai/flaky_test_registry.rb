# frozen_string_literal: true

require "json"

module Henitai
  # The set of test files whose outcome differed between two baseline runs.
  #
  # Produced by comparing per-file pass/fail maps from two runs of the same
  # suite, and persisted as `henitai_flaky_tests.json` so that later runs can
  # tell a kill caused by a flaky test from one caused by a stable test.
  class FlakyTestRegistry
    FILE_NAME = "henitai_flaky_tests.json"

    def self.from_outcomes(first, second)
      shared = first.keys & second.keys
      flaky = shared.reject { |file| first[file] == second[file] }
      new(flaky)
    end

    def self.load(path)
      return new([]) unless File.file?(path)

      new(Array(JSON.parse(File.read(path))["flaky_tests"]))
    end

    def self.for_config(config)
      return new([]) unless config.respond_to?(:flaky_detection) && config.flaky_detection

      for_reports_dir(config.respond_to?(:reports_dir) ? config.reports_dir : nil)
    end

    def self.for_reports_dir(dir)
      return new([]) if dir.nil?

      load(File.join(dir, FILE_NAME))
    end

    def initialize(files)
      @files = files.map { |file| File.expand_path(file) }.uniq.sort.freeze
      @lookup = @files.to_set.freeze
    end

    def all
      @files
    end

    def flaky?(path)
      @lookup.include?(File.expand_path(path))
    end

    def empty?
      @files.empty?
    end

    def write(path)
      File.write(path, JSON.pretty_generate("flaky_tests" => @files))
    end
  end
end
