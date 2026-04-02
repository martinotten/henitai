# frozen_string_literal: true

module Henitai
  # Temporarily suppresses noisy warnings emitted by third-party libraries.
  module WarningSilencer
    def self.silence
      original_stderr = $stderr
      File.open(File::NULL, "w") do |sink|
        $stderr = sink
        yield
      end
    ensure
      $stderr = original_stderr
    end
  end
end
