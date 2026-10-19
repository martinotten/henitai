# frozen_string_literal: true

require "fileutils"
require "minitest"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Integration::MinitestRunnableFilter, :aggregate_failures do
  def suite_defined_in(path, method_name = "test_it")
    Class.new do
      class_eval("def #{method_name}; end", path, 1) # rubocop:disable Style/EvalWithLocation

      def self.runnable_methods = instance_methods(false).map(&:to_s)
    end
  end

  def with_registry(*suites)
    registry = suites.dup
    allow(Minitest::Runnable).to receive(:runnables).and_return(registry)
    yield registry
  end

  it "keeps the test classes defined in the wanted files only" do
    Dir.mktmpdir do |dir|
      wanted = File.join(dir, "a_test.rb")
      other = File.join(dir, "b_test.rb")
      FileUtils.touch([wanted, other])
      kept = suite_defined_in(wanted)

      with_registry(kept, suite_defined_in(other)) do |registry|
        described_class.new([wanted]).apply!

        expect(registry).to eq([kept])
      end
    end
  end

  it "matches a file through a symlinked directory" do
    Dir.mktmpdir do |dir|
      real = File.join(dir, "real")
      FileUtils.mkdir_p(real)
      FileUtils.touch(File.join(real, "a_test.rb"))
      File.symlink(real, File.join(dir, "link"))
      kept = suite_defined_in(File.join(real, "a_test.rb"))

      with_registry(kept) do |registry|
        described_class.new([File.join(dir, "link", "a_test.rb")]).apply!

        expect(registry).to eq([kept])
      end
    end
  end

  it "drops classes without test methods and classes that cannot list them" do
    empty = Class.new { def self.runnable_methods = [] }
    abstract = Class.new { def self.runnable_methods = raise(NotImplementedError) }

    with_registry(empty, abstract) do |registry|
      described_class.new(["a_test.rb"]).apply!

      expect(registry).to be_empty
    end
  end

  it "drops a class whose test method has no source location" do
    builtin = Class.new { def self.runnable_methods = ["hash"] }

    with_registry(builtin) do |registry|
      described_class.new(["a_test.rb"]).apply!

      expect(registry).to be_empty
    end
  end

  it "supplies a seed while listing methods and restores it afterwards" do
    seen = []
    suite = Class.new { define_singleton_method(:runnable_methods) { (seen << Minitest.seed) && [] } }
    original = Minitest.seed
    Minitest.seed = nil

    with_registry(suite) { described_class.new(["a_test.rb"]).apply! }

    expect([seen.first.class, Minitest.seed]).to eq([Integer, nil])
  ensure
    Minitest.seed = original
  end
end
