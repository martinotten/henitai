# frozen_string_literal: true

require "simplecov"

SimpleCov.coverage_dir(ENV.fetch("HENITAI_COVERAGE_DIR", "coverage"))
SimpleCov.start do
  add_filter "/spec/"
end
