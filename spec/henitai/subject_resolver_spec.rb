# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::SubjectResolver do
  def write_source(dir, relative_path, source)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  it "resolves nested namespaces and method types from source files" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          module Foo
            class Bar
              def baz
                1
              end

              def self.qux = 2

              module Nested
                def quux = 3
              end
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects.map(&:expression)).to eq(
        [
          "Foo::Bar#baz",
          "Foo::Bar.qux",
          "Foo::Bar::Nested#quux"
        ]
      )
    end
  end

  it "preserves source location metadata for each subject" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            def bar
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects.map(&:source_range)).to eq([2..3])
    end
  end

  it "resolves methods inside singleton classes as class subjects" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            class Bar
              class << self
                def qux
                end
              end
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects.map(&:expression)).to eq(["Foo::Bar.qux"])
    end
  end

  it "ignores top-level methods without namespace context" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          def top_level
          end

          def self.top_level_class
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects).to be_empty
    end
  end

  it "resolves compact nested namespace declarations" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          module Foo::Bar
            def baz
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects.map(&:expression)).to eq(["Foo::Bar#baz"])
    end
  end

  it "keeps sibling instance methods out of singleton-class context" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            class << self
              def bar
              end
            end

            def baz
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects.map(&:expression)).to eq(
        [
          "Foo.bar",
          "Foo#baz"
        ]
      )
    end
  end

  it "resolves root-qualified namespaces" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          module ::Foo
            def baz
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects.map(&:expression)).to eq(["Foo#baz"])
    end
  end

  it "ignores anonymous classes and generated methods while keeping explicit defs" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            class << self
              def bar = 1
            end

            Class.new do
              def hidden = 2
            end
          end

          class Foo
            attr_accessor :generated

            def baz = 3
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects.map(&:expression)).to eq(
        [
          "Foo.bar",
          "Foo#baz"
        ]
      )
    end
  end

  it "filters subjects by an exact expression" do
    subjects = [
      Henitai::Subject.parse("Foo#bar"),
      Henitai::Subject.parse("Foo.bar"),
      Henitai::Subject.parse("Foo::Bar#baz")
    ]

    filtered = described_class.new.apply_pattern(subjects, "Foo#bar")

    expect(filtered.map(&:expression)).to eq(["Foo#bar"])
  end

  it "filters subjects by a namespace wildcard expression" do
    subjects = [
      Henitai::Subject.parse("Foo#bar"),
      Henitai::Subject.parse("Foo.bar"),
      Henitai::Subject.parse("Foo::Bar#baz"),
      Henitai::Subject.parse("Bar#qux")
    ]

    filtered = described_class.new.apply_pattern(subjects, "Foo*")

    expect(filtered.map(&:expression)).to eq(
      [
        "Foo#bar",
        "Foo.bar",
        "Foo::Bar#baz"
      ]
    )
  end

  it "skips subjects without namespace metadata when applying a wildcard" do
    subjects = [
      Henitai::Subject.new(method_name: "bar"),
      Henitai::Subject.parse("Foo#baz")
    ]

    filtered = described_class.new.apply_pattern(subjects, "Foo*")

    expect(filtered.map(&:expression)).to eq(["Foo#baz"])
  end

  it "does not match similarly prefixed namespaces for a wildcard" do
    subjects = [Henitai::Subject.parse("FooBar#baz")]

    filtered = described_class.new.apply_pattern(subjects, "Foo*")

    expect(filtered).to be_empty
  end
end
