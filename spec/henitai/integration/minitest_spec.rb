# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Integration::Minitest do
  def with_temp_workspace
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { yield dir }
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
