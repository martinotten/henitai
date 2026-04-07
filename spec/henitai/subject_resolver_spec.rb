# frozen_string_literal: true

require "fileutils"
require "parser/current"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::SubjectResolver do
  def write_source(dir, relative_path, source)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  it "returns false for anonymous class blocks without a callable send node" do
    node = Struct.new(:type, :children).new(:block, [nil])

    expect(described_class.new.send(:anonymous_class_block?, node)).to be(false)
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

  it "extracts root-qualified constant names" do
    resolver = described_class.new
    node = Parser::CurrentRuby.parse("::Foo")

    expect(resolver.send(:constant_name, node)).to eq("Foo")
    expect(resolver.send(:constant_name, node.children.first)).to eq("")
    expect(
      resolver.send(:constant_name, Parser::CurrentRuby.parse("::Foo::Bar"))
    ).to eq("Foo::Bar")
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

  it "resolves define_method subjects with static names" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            define_method(:bar) do
              1
            end

            class << self
              define_method("baz") do
                2
              end
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects.map(&:expression)).to eq(
        [
          "Foo#bar",
          "Foo.baz"
        ]
      )
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

  it "ignores define_method calls on non-self receivers" do
    node = Parser::CurrentRuby.parse("other.define_method(:bar)")

    expect(described_class.new.send(:define_method_call?, node)).to be(false)
  end

  it "returns false for malformed define_method calls" do
    resolver = described_class.new
    malformed = Struct.new(:type, :children).new(:int, [])

    expect(resolver.send(:define_method_call?, nil)).to be(false)
    expect(resolver.send(:define_method_call?, malformed)).to be(false)
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

            Struct.new(:token) do
              def struct_hidden = 3
            end

            Data.define(:value) do
              def data_hidden = 4
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

  it "strips a leading colon from symbol names" do
    expect(described_class.new.send(:symbol_name, ":foo")).to eq("foo")
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

  it "does not suppress methods in blocks attached to non-constructor Class calls" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", <<~RUBY)
        class Foo
          Class.configure do
            def bar = 1
          end
        end
      RUBY

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects.map(&:expression)).to include("Foo#bar")
    end
  end

  it "resolves self.define_method as a subject" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", <<~RUBY)
        class Foo
          self.define_method(:bar) do
            1
          end
        end
      RUBY

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects.map(&:expression)).to include("Foo#bar")
    end
  end

  it "ignores define_method with a dynamic method name" do
    Dir.mktmpdir do |dir|
      path = write_source(dir, "lib/sample.rb", <<~RUBY)
        class Foo
          name = :generated
          define_method(name) do
            1
          end
        end
      RUBY

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects).to be_empty
    end
  end
end
