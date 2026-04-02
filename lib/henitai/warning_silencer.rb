# frozen_string_literal: true

module Henitai
  # Temporarily suppresses noisy warnings emitted by third-party libraries.
  module WarningSilencer
    def self.silence
      original_stderr = $stderr
      sink = File.open(File::NULL, "w")
      $stderr = sink
      yield
    ensure
      $stderr = original_stderr if original_stderr
      sink&.close
    end
  end
end
