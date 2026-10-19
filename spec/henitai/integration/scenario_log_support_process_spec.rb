# frozen_string_literal: true

require "open3"
require "timeout"
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

  it "drains output without calling IO.select, which tests may stub" do
    script = <<~'RUBY'
      require "tmpdir"
      require "henitai"
      require "henitai/integration"

      calls = 0
      IO.singleton_class.prepend(Module.new { define_method(:select) { |*args| (calls += 1) && super(*args) } })

      Dir.mktmpdir do |dir|
        Henitai::Integration::ScenarioLogSupport.new.capture_child_output(
          stdout_path: File.join(dir, "stdout.log"),
          stderr_path: File.join(dir, "stderr.log"),
          log_path: File.join(dir, "combined.log")
        ) { puts "inside"; sleep 0.1 }
      end

      $stdout.puts "select_calls=#{calls}"
    RUBY

    stdout, stderr, status = Open3.capture3("bundle", "exec", "ruby", "-I", "lib", "-e", script)

    expect([status.success?, stdout[/select_calls=\d+/]]).to eq([true, "select_calls=0"]), stderr
  end

  it "does not wait for a background grandchild holding the pipes" do
    script = <<~'RUBY'
      require "tmpdir"
      require "henitai"
      require "henitai/integration"

      support = Henitai::Integration::ScenarioLogSupport.new
      Dir.mktmpdir do |dir|
        stdout_path = File.join(dir, "stdout.log")
        started = nil
        support.capture_child_output(
          stdout_path: stdout_path,
          stderr_path: File.join(dir, "stderr.log"),
          log_path: File.join(dir, "combined.log")
        ) do
          puts "before grandchild"
          spawn("sleep 5")
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        puts "#{elapsed < 0.5} #{File.read(stdout_path).inspect}"
      end
    RUBY

    stdout, _, status = Timeout.timeout(30) do
      Open3.capture3("bundle", "exec", "ruby", "-I", "lib", "-e", script)
    end

    expect([status.success?, stdout.lines.last]).to eq([true, "true \"before grandchild\\n\"\n"])
  end
end
