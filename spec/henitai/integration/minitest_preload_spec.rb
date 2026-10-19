# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Integration::MinitestPreload, :aggregate_failures do
  let(:host_class) do
    Class.new do
      include Henitai::Integration::MinitestPreload

      attr_reader :minitest_preloaded

      def subprocess_env = { "HENITAI_PRELOAD_SPEC_ENV" => "1" }
    end
  end
  let(:host) { host_class.new }

  before do
    allow(Henitai::Integration::MinitestAutorun).to receive(:suppress!)
    allow(Henitai::Integration::CoverageRuntimeSuppressors).to receive_messages(
      suppress_simplecov!: nil, suppress_coverage!: nil
    )
    allow(Henitai::Integration::MinitestLoadPath).to receive(:ensure!)
    allow(Henitai::Integration::RailsEnvironmentPreloader).to receive(:new)
      .and_return(instance_double(Henitai::Integration::RailsEnvironmentPreloader, call: nil))
  end

  after { %w[HENITAI_PRELOAD_SPEC_ENV HENITAI_PRELOAD_SPEC_LOADED].each { |key| ENV.delete(key) } }

  it "is supported" do
    expect(host.fork_server_supported?).to be(true)
  end

  it "suppresses autorun and coverage, then loads the test files without running them" do
    Dir.mktmpdir do |dir|
      file = File.join(dir, "preload_test.rb")
      File.write(file, "ENV[\"HENITAI_PRELOAD_SPEC_LOADED\"] = \"1\"\n")

      host.preload_environment([file])

      expect(ENV.fetch("HENITAI_PRELOAD_SPEC_LOADED")).to eq("1")
      expect(Henitai::Integration::MinitestAutorun).to have_received(:suppress!)
      expect(Henitai::Integration::CoverageRuntimeSuppressors).to have_received(:suppress_coverage!)
      expect(ENV.fetch("HENITAI_PRELOAD_SPEC_ENV")).to eq("1")
    ensure
      $LOADED_FEATURES.delete(File.expand_path(file))
    end
  end

  it "lets a failing test file abort the boot" do
    Dir.mktmpdir do |dir|
      file = File.join(dir, "broken_test.rb")
      File.write(file, "raise 'boom'\n")

      expect { host.preload_environment([file]) }.to raise_error(RuntimeError, "boom")
    end
  end
end
