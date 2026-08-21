# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Integration::LoadedFeatures do
  subject(:loaded_features) { described_class.new }

  let!(:original_loaded_features) { $LOADED_FEATURES.dup }

  before { $LOADED_FEATURES.clear }

  after { $LOADED_FEATURES.replace(original_loaded_features) }

  describe "#include?" do
    it "matches when a feature entry is expanded in $LOADED_FEATURES" do
      $LOADED_FEATURES << File.expand_path("spec/foo_spec.rb")

      expect(loaded_features.include?("spec/foo_spec.rb")).to be(true)
    end

    it "matches when a feature entry is raw in $LOADED_FEATURES" do
      $LOADED_FEATURES << "spec/foo_spec.rb"

      expect(loaded_features.include?("spec/foo_spec.rb")).to be(true)
    end

    it "returns false when no candidate matches" do
      expect(loaded_features.include?("nonexistent/file.rb")).to be(false)
    end

    it "handles an expanded path passed as the file argument" do
      target_path = File.expand_path("spec/foo_spec.rb")
      $LOADED_FEATURES << target_path

      expect(loaded_features.include?(target_path)).to be(true)
    end

    it "handles a .rb-suffixed candidate built from the raw file argument" do
      base = "/tmp/dummy_loaded_feature_test"
      $LOADED_FEATURES << "#{base}.rb"

      expect(loaded_features.include?(base)).to be(true)
    end

    it "handles a .rb-suffixed candidate built from the expanded file argument" do
      base = "dummy_loaded_feature_expanded"
      $LOADED_FEATURES << "#{File.expand_path(base)}.rb"

      expect(loaded_features.include?(base)).to be(true)
    end

    it "matches via the normalized candidate only, when the raw feature string matches nothing" do
      file = "spec/other_file_spec"
      feature = "totally/unrelated/path.rb"
      $LOADED_FEATURES << feature
      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with(feature).and_return(File.expand_path(file))

      expect(loaded_features.include?(file)).to be(true)
    end

    it "matches via the raw feature only, when the normalized candidate matches nothing" do
      file = "spec/real_file_spec"
      feature = "#{file}.rb"
      $LOADED_FEATURES << feature
      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with(feature).and_return("/nowhere/unrelated.rb")

      expect(loaded_features.include?(file)).to be(true)
    end

    # The feature deliberately does not match any candidate raw, so the `||`
    # cannot short-circuit and #normalize really runs. The ported version of
    # this example used a self-matching feature string and passed with the
    # rescue deleted.
    it "does not raise when File.expand_path fails on an unrelated loaded feature" do
      bad_feature = "unrelated/broken.rb"
      $LOADED_FEATURES << bad_feature
      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with(bad_feature).and_raise(ArgumentError, "invalid byte sequence")

      expect(loaded_features.include?("spec/foo_spec")).to be(false)
    end
  end

  describe "#map" do
    it "pairs each file with its #include? result, preserving input order" do
      $LOADED_FEATURES << File.expand_path("b.rb")

      expect(loaded_features.map(["a.rb", "b.rb", "c.rb"]))
        .to eq([["a.rb", false], ["b.rb", true], ["c.rb", false]])
    end

    it "returns an empty list for no files" do
      expect(loaded_features.map([])).to eq([])
    end
  end
end
