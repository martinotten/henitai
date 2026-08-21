# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SubjectSelection do
  def build_subject(expression, source_file: "lib/foo.rb")
    Henitai::Subject.new(expression: expression, source_location: { file: source_file, range: 1..3 })
  end

  def build_pattern(expression) = Struct.new(:expression).new(expression)

  def build_resolver(resolved:, patterns: {})
    instance_double(Henitai::SubjectResolver).tap do |resolver|
      allow(resolver).to receive(:resolve_from_files).and_return(resolved)
      patterns.each do |expression, matched|
        allow(resolver).to receive(:apply_pattern).with(resolved, expression).and_return(matched)
      end
    end
  end

  describe "#resolve" do
    it "returns every resolved subject when no patterns are given" do
      resolved = [build_subject("Greeter#hello"), build_subject("Greeter#bye")]
      selection = described_class.new(subject_resolver: build_resolver(resolved: resolved), patterns: [])

      expect(selection.resolve(["lib/foo.rb"])).to eq(resolved)
    end

    it "treats nil patterns as no patterns" do
      resolved = [build_subject("Greeter#hello")]
      selection = described_class.new(subject_resolver: build_resolver(resolved: resolved), patterns: nil)

      expect(selection.resolve(["lib/foo.rb"])).to eq(resolved)
    end

    it "passes the source files straight through to the resolver" do
      resolver = build_resolver(resolved: [])
      described_class.new(subject_resolver: resolver, patterns: []).resolve(%w[lib/a.rb lib/b.rb])

      expect(resolver).to have_received(:resolve_from_files).with(%w[lib/a.rb lib/b.rb])
    end

    it "applies each pattern independently and concatenates the matches" do
      hello = build_subject("Greeter#hello")
      bye = build_subject("Greeter#bye")
      resolver = build_resolver(
        resolved: [hello, bye], patterns: { "Greeter#hello" => [hello], "Greeter#bye" => [bye] }
      )
      selection = described_class.new(
        subject_resolver: resolver,
        patterns: [build_pattern("Greeter#hello"), build_pattern("Greeter#bye")]
      )

      expect(selection.resolve(["lib/foo.rb"])).to eq([hello, bye])
    end

    it "de-duplicates a subject matched by two overlapping patterns" do
      hello = build_subject("Greeter#hello")
      resolver = build_resolver(
        resolved: [hello], patterns: { "Greeter*" => [hello], "Greeter#hello" => [hello] }
      )
      selection = described_class.new(
        subject_resolver: resolver,
        patterns: [build_pattern("Greeter*"), build_pattern("Greeter#hello")]
      )

      expect(selection.resolve(["lib/foo.rb"])).to eq([hello])
    end

    it "returns nothing when the patterns match nothing" do
      resolver = build_resolver(resolved: [build_subject("Greeter#hello")], patterns: { "Other*" => [] })
      selection = described_class.new(subject_resolver: resolver, patterns: [build_pattern("Other*")])

      expect(selection.resolve(["lib/foo.rb"])).to eq([])
    end
  end

  describe "#unique" do
    subject(:selection) { described_class.new(subject_resolver: build_resolver(resolved: []), patterns: []) }

    # Expression alone is not a sufficient key: the same expression can appear
    # in two files, and both are real subjects.
    it "keeps subjects with the same expression when they are in different source files" do
      first = build_subject("Greeter#hello", source_file: "lib/foo.rb")
      second = build_subject("Greeter#hello", source_file: "lib/bar.rb")
      duplicate = build_subject("Greeter#hello", source_file: "lib/foo.rb")

      expect(selection.unique([first, second, duplicate])).to eq([first, second])
    end

    it "keeps subjects in the same file with different expressions" do
      hello = build_subject("Greeter#hello")
      bye = build_subject("Greeter#bye")

      expect(selection.unique([hello, bye])).to eq([hello, bye])
    end

    it "keeps the first of a duplicate pair, not the last" do
      first = build_subject("Greeter#hello")
      duplicate = build_subject("Greeter#hello")

      expect(selection.unique([first, duplicate]).first).to be(first)
    end
  end
end
