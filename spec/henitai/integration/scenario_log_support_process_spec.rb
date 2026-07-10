# frozen_string_literal: true

require "open3"
require "spec_helper"

RSpec.describe Henitai::Integration::ScenarioLogSupport do
  it "keeps stdout and stderr usable after capturing child output" do
    script = <<~RUBY
      require "tmpdir"
      require "henitai"
      require "henitai/integration"

      support = Henitai::Integration::ScenarioLogSupport.new

      Dir.mktmpdir do |dir|
        support.capture_child_output(
          stdout_path: File.join(dir, "stdout.log"),
          stderr_path: File.join(dir, "stderr.log"),
          log_path: File.join(dir, "combined.log")
        ) do
          puts "inside"
          warn "inside err"
        end

        puts "after"
        warn "after err"
      end
    RUBY

    stdout, stderr, status = Open3.capture3(
      "bundle", "exec", "ruby", "-I", "lib", "-e", script
    )

    expect(status.success?).to be(true), [stdout, stderr].reject(&:empty?).join("\n")
  end
end
