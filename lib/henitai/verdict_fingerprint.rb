# frozen_string_literal: true

require "digest"
require "json"

module Henitai
  # Content fingerprints that decide whether a stored Killed verdict is still
  # trustworthy: the subject's source (method body) and the covering test
  # files must both be byte-identical to what was recorded. Any read failure
  # yields nil / a mismatch — conservative, never reuse on doubt.
  module VerdictFingerprint
    module_function

    # SHA256 of the subject's source lines. nil when the subject has no
    # source range or the file cannot be read.
    def subject_source_hash(mutant)
      subject = mutant.subject
      return nil unless subject.respond_to?(:source_file) && subject.respond_to?(:source_range)

      range = subject.source_range
      return nil unless range

      lines = File.readlines(subject.source_file)
      Digest::SHA256.hexdigest(lines[(range.begin - 1)..(range.end - 1)].to_a.join)
    rescue StandardError
      nil
    end

    # JSON fingerprint of the covering test files: their sorted paths plus a
    # combined content hash. nil when no tests are known or any is unreadable.
    def tests_fingerprint(test_files)
      paths = Array(test_files).map(&:to_s).sort
      return nil if paths.empty?

      sha = combined_content_sha(paths)
      return nil unless sha

      JSON.generate("paths" => paths, "sha" => sha)
    end

    # True when every recorded test file still exists with identical content.
    def tests_fingerprint_current?(fingerprint_json)
      return false if fingerprint_json.nil?

      fingerprint = JSON.parse(fingerprint_json)
      combined_content_sha(fingerprint.fetch("paths")) == fingerprint.fetch("sha")
    rescue StandardError
      false
    end

    def combined_content_sha(paths)
      digest = Digest::SHA256.new
      paths.each do |path|
        content = File.read(path)
        digest.update(path.bytesize.to_s)
        digest.update(":")
        digest.update(path)
        digest.update(content.bytesize.to_s)
        digest.update(":")
        digest.update(content)
      end
      digest.hexdigest
    rescue StandardError
      nil
    end
  end
end
