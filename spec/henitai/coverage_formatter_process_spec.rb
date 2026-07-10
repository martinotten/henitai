# frozen_string_literal: true

require "open3"
require "spec_helper"

RSpec.describe Henitai::CoverageFormatter do
  it "can be required without rspec/core being available" do
    script = <<~RUBY
      module Kernel
        alias __henitai_original_require__ require

        def require(path)
          raise LoadError, "blocked rspec/core" if path == "rspec/core"

          __henitai_original_require__(path)
        end
      end

      require "henitai/coverage_formatter"
      puts "ok"
    RUBY

    stdout, stderr, status = Open3.capture3(
      "ruby", "-I", "lib", "-e", script, chdir: Dir.pwd
    )

    aggregate_failures do
      expect(status.success?).to be(true), stderr
      expect(stdout).to eq("ok\n")
    end
  end
end
