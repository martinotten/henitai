# frozen_string_literal: true

require "fileutils"
require "minitest"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Integration::MinitestTestRunner do
  subject(:runner) { described_class.new }

  def with_temp_workspace
    Dir.mktmpdir { |dir| Dir.chdir(dir) { yield dir } }
  end

  def write_test_file(dir, relative_path)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# noop\n")
    path
  end

  def stub_minitest_run(return_value)
    allow(Minitest).to receive(:run).and_return(return_value)
  end

  describe "#call" do
    context "when Minitest.run returns an Integer" do
      it "returns that integer" do
        stub_minitest_run(7)

        expect(runner.call([])).to eq(7)
      end
    end

    context "when Minitest.run returns true" do
      it "returns 0" do
        stub_minitest_run(true)

        expect(runner.call([])).to eq(0)
      end
    end

    context "when Minitest.run returns false" do
      it "returns 1" do
        stub_minitest_run(false)

        expect(runner.call([])).to eq(1)
      end
    end

    it "requires every test file by its expanded path" do
      with_temp_workspace do |dir|
        a_test = write_test_file(dir, "test/a_test.rb")
        b_test = write_test_file(dir, "test/b_test.rb")
        stub_minitest_run(true)

        runner.call([a_test, b_test])

        expect($LOADED_FEATURES).to include(File.expand_path(a_test), File.expand_path(b_test))
      end
    end

    it "suppresses Minitest autorun so it is safe to call repeatedly" do
      stub_minitest_run(true)

      runner.call([])
      runner.call([])

      expect(Minitest.autorun).to be_nil
    end
  end
end
