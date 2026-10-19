# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"

# The baseline loads the coverage formatter and reporter with `-r` before the
# spec helper requires "henitai". Whatever they load must not shadow the
# autoloaded Integration namespace.
RSpec.describe Henitai::CoverageFormatter do
  def run_ruby(entry_point, script)
    lib = File.expand_path("../../lib", __dir__)
    Open3.capture3(RbConfig.ruby, "-I", lib, "-r", entry_point, "-e", script)
  end

  it "keeps Integration autoloadable after the RSpec formatter" do
    script = 'require "henitai"; puts Henitai::Integration::Rspec.name'
    stdout, stderr, status = run_ruby("henitai/rspec_coverage_formatter", script)

    expect([stdout.strip, status.success?]).to eq(["Henitai::Integration::Rspec", true]), stderr
  end

  it "keeps Integration autoloadable after the Minitest reporter" do
    script = 'require "henitai"; puts Henitai::Integration::Minitest.name'
    stdout, stderr, status = run_ruby("henitai/minitest_coverage_reporter", script)

    expect([stdout.strip, status.success?]).to eq(["Henitai::Integration::Minitest", true]), stderr
  end
end
