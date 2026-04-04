# frozen_string_literal: true

require "fileutils"
require "open3"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Integration::Minitest do
  def with_temp_workspace
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { yield dir }
    end
  end

  def with_env(key, value)
    original = ENV.fetch(key, nil)

    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end

    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end

  def write_file(dir, relative_path, source)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  def sample_source
    <<~RUBY
      class Sample
        def value
        end
      end
    RUBY
  end

  def minitest_source
    <<~RUBY
      require "minitest/autorun"
      require_relative "../lib/sample"

      class SampleTest < Minitest::Test
        def test_value
        end
      end
    RUBY
  end

  def require_source
    <<~RUBY
      require "minitest/autorun"
      require "lib/sample"

      class SampleTest < Minitest::Test
        def test_value
        end
      end
    RUBY
  end

  def write_sample_library(dir)
    write_file(dir, "lib/sample.rb", sample_source)
  end

  def stub_minitest_run(order)
    allow(Minitest).to receive(:run) do |argv|
      order << [:minitest, argv]
      true
    end
  end

  def stub_minitest_process_flow(order, test_file)
    stub_minitest_exit(order)
    stub_minitest_fork(order)
    stub_minitest_wait(order)
    stub_minitest_status
    stub_minitest_requires(order)
    stub_minitest_run(order)
    write_sample_library(File.dirname(test_file, 2))
  end

  def stub_minitest_exit(order)
    allow(Process).to receive(:exit) { |status| order << [:exit, status] }
  end

  def stub_minitest_fork(order)
    allow(Process).to receive(:fork) do |&block|
      order << :fork
      block.call
      12_345
    end
  end

  def stub_minitest_wait(order)
    allow(Process).to receive(:wait) do |pid, flags = nil|
      order << [:wait, pid, flags]
      pid
    end
  end

  def stub_minitest_status
    allow(Process).to receive(:last_status).and_return(
      Struct.new(:success?).new(true)
    )
  end

  def stub_minitest_requires(order)
    allow(Henitai::Mutant::Activator).to receive(:activate!) do |_mutant|
      order << :activate
    end
    allow(Kernel).to receive(:require).and_return(true)
  end

  it "selects minitest files by subject prefix" do
    with_temp_workspace do |dir|
      write_file(dir, "test/sample_test.rb", minitest_source)
      write_file(dir, "test/other_test.rb", minitest_source.sub("Sample", "Other"))

      subject = Henitai::Subject.parse("Sample#value")

      expect(described_class.new.select_tests(subject)).to eq(["test/sample_test.rb"])
    end
  end

  it "falls back to tests that require the source file" do
    with_temp_workspace do |dir|
      source_file = write_sample_library(dir)
      write_file(dir, "test/widget_test.rb", require_source)

      subject = Henitai::Subject.new(
        namespace: "Widget",
        method_name: "value",
        source_location: {
          file: source_file,
          range: nil
        }
      )

      expect(described_class.new.select_tests(subject)).to eq(["test/widget_test.rb"])
    end
  end

  it "builds the minitest baseline suite command" do
    integration = described_class.new

    expect(integration.send(:suite_command, ["test/sample_test.rb"])).to eq(
      [
        "bundle",
        "exec",
        "ruby",
        "-I",
        "test",
        "-r",
        "henitai/minitest_simplecov",
        "-e",
        "ARGV.each { |f| require File.expand_path(f) }",
        "test/sample_test.rb"
      ]
    )
  end

  it "spawns the baseline suite with the minitest subprocess environment" do
    integration = described_class.new

    with_temp_workspace do
      allow(Process).to receive(:spawn).and_return(4321)
      allow(integration).to receive(:wait_with_timeout).and_return(:timeout)

      integration.run_suite(["test/sample_test.rb"], timeout: 4.0)

      expect(Process).to have_received(:spawn).with(
        integration.send(:subprocess_env),
        *integration.send(:suite_command, ["test/sample_test.rb"]),
        out: kind_of(File),
        err: kind_of(File)
      )
    end
  end

  it "requires config/environment.rb only when it exists" do
    integration = described_class.new
    env_file = File.expand_path("config/environment.rb")

    allow(File).to receive(:exist?).with(env_file).and_return(true)

    expect(integration).to receive(:require).with(env_file)

    integration.send(:preload_environment)
  end

  it "adds the test directory to the load path only once" do
    integration = described_class.new
    original_load_path = $LOAD_PATH.dup
    test_dir = File.expand_path("test")

    $LOAD_PATH.replace(original_load_path.reject { |path| path == test_dir })

    2.times { integration.send(:setup_load_path) }

    expect($LOAD_PATH.count(test_dir)).to eq(1)
  ensure
    $LOAD_PATH.replace(original_load_path)
  end

  it "sets subprocess defaults for baseline runs" do
    with_env("RAILS_ENV", nil) do
      expect(described_class.new.send(:subprocess_env)).to eq(
        "RAILS_ENV" => "test",
        "PARALLEL_WORKERS" => "1"
      )
    end
  end

  it "lists minitest test files and excludes system tests" do
    with_temp_workspace do |dir|
      write_file(dir, "test/models/sample_test.rb", "")
      write_file(dir, "test/models/sample_spec.rb", "")
      write_file(dir, "test/system/browser_test.rb", "")

      expect(described_class.new.test_files).to match_array(
        ["test/models/sample_test.rb", "test/models/sample_spec.rb"]
      )
    end
  end

  it "boots the minitest integration when rspec/core is unavailable" do
    script = <<~RUBY
      module Kernel
        alias __henitai_original_require__ require

        def require(path)
          raise LoadError, "blocked rspec/core" if path == "rspec/core"

          __henitai_original_require__(path)
        end
      end

      require "henitai"
      require "henitai/integration"

      command = Henitai::Integration::Minitest.new.send(
        :suite_command,
        ["test/sample_test.rb"]
      )
      puts command.last
    RUBY

    stdout, stderr, status = Open3.capture3(
      "ruby",
      "-I",
      "lib",
      "-e",
      script,
      chdir: Dir.pwd
    )

    aggregate_failures do
      expect(status.success?).to be(true), stderr
      expect(stdout).to eq("test/sample_test.rb\n")
    end
  end

  it "activates the mutant before requiring the test files" do
    with_temp_workspace do |dir|
      test_file = write_file(dir, "test/sample_test.rb", minitest_source)
      mutant = Struct.new(:id).new("mutant-1")
      integration = described_class.new
      order = []
      original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

      begin
        stub_minitest_process_flow(order, test_file)

        integration.run_mutant(
          mutant:,
          test_files: [test_file],
          timeout: 1.0
        )

        expect(order).to eq(
          [
            :fork,
            :activate,
            [:minitest, []],
            [:exit, 0],
            [:wait, 12_345, Process::WNOHANG]
          ]
        )
      ensure
        ENV["HENITAI_MUTANT_ID"] = original_env
      end
    end
  end
end
