# frozen_string_literal: true

# rubocop:disable Metrics/MethodLength, RSpec/MultipleExpectations
require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::SurvivorActivationCache do
  def build_stub_subject
    instance_double(
      Henitai::Subject,
      namespace: "MyModule",
      method_name: "foo",
      method_type: :instance,
      source_file: "lib/my_module.rb"
    )
  end

  def build_survived_mutant(stable_id:, activation_source:)
    mutant = instance_double(
      Henitai::Mutant,
      stable_id:,
      subject: build_stub_subject,
      operator: "ArithmeticOperator",
      description: "+ to -",
      location: {
        file: "lib/my_module.rb",
        start_line: 10,
        end_line: 10,
        start_col: 4,
        end_col: 9
      },
      covered_by: ["spec/my_module_spec.rb"],
      survived?: true
    )
    allow(Henitai::Mutant::Activator)
      .to receive(:activation_source_for)
      .with(mutant)
      .and_return(activation_source)
    mutant
  end

  describe ".compute" do
    it "returns a hash of stable_id → recipe for each mutant" do
      mutant = build_survived_mutant(
        stable_id: "abc123",
        activation_source: "define_method(:foo) do\n  nil\nend\n"
      )

      result = described_class.compute([mutant])

      expect(result.keys).to eq(["abc123"])
      expect(result["abc123"]["activationSource"]).to eq("define_method(:foo) do\n  nil\nend\n")
      expect(result["abc123"]["namespace"]).to eq("MyModule")
      expect(result["abc123"]["methodName"]).to eq("foo")
      expect(result["abc123"]["methodType"]).to eq("instance")
      expect(result["abc123"]["operator"]).to eq("ArithmeticOperator")
    end

    it "skips mutants for which activation_source_for returns nil" do
      mutant = build_survived_mutant(stable_id: "abc", activation_source: nil)
      expect(described_class.compute([mutant])).to be_empty
    end

    it "returns an empty hash for an empty mutant list" do
      expect(described_class.compute([])).to eq({})
    end

    it "serializes the location with camelCase keys" do
      mutant = build_survived_mutant(
        stable_id: "loc-test",
        activation_source: "define_method(:foo) do\n  nil\nend\n"
      )

      recipe = described_class.compute([mutant])["loc-test"]

      expect(recipe["location"]).to eq(
        "file" => "lib/my_module.rb",
        "startLine" => 10,
        "endLine" => 10,
        "startCol" => 4,
        "endCol" => 9
      )
    end

    it "includes coveredBy as an array" do
      mutant = build_survived_mutant(
        stable_id: "cov-test",
        activation_source: "define_method(:foo) do\n  nil\nend\n"
      )

      recipe = described_class.compute([mutant])["cov-test"]

      expect(recipe["coveredBy"]).to eq(["spec/my_module_spec.rb"])
    end
  end

  describe ".load" do
    it "returns nil when the file does not exist" do
      expect(described_class.load("/no/such/path.json")).to be_nil
    end

    it "returns nil when the file contains invalid JSON" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "recipes.json")
        File.write(path, "not json{{{")
        expect(described_class.load(path)).to be_nil
      end
    end

    it "parses and returns a valid recipe file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "recipes.json")
        recipes = { "abc" => { "activationSource" => "define_method(:foo) do\n  nil\nend\n" } }
        File.write(path, JSON.pretty_generate(recipes))

        result = described_class.load(path)
        expect(result["abc"]["activationSource"]).to eq("define_method(:foo) do\n  nil\nend\n")
      end
    end
  end

  describe ".write" do
    it "writes recipes as pretty JSON and creates intermediate directories" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "sessions", "abc-123", described_class::FILENAME)
        recipes = { "id1" => { "activationSource" => "source" } }

        described_class.write(path, recipes)

        written = JSON.parse(File.read(path))
        expect(written["id1"]["activationSource"]).to eq("source")
      end
    end
  end
end
# rubocop:enable Metrics/MethodLength, RSpec/MultipleExpectations
