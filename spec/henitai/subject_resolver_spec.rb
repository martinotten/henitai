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

  describe "lexical scope" do
    def scopes_for(source)
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/sample.rb", source)
        described_class.new.resolve_from_files([path]).to_h { |subject| [subject.expression, subject.lexical_scope] }
      end
    end

    it "records the openers of the modules and classes around a method" do
      scopes = scopes_for(<<~RUBY)
        module Outer
          class Inner < Base
            def value = 1
            def self.build = 2
            class << self
              def make = 3
            end
          end
        end
      RUBY

      expect(scopes).to eq(
        "Outer::Inner#value" => ["module Outer", "class Inner"],
        "Outer::Inner.build" => ["module Outer", "class Inner"],
        "Outer::Inner.make" => ["module Outer", "class Inner", "class << self"]
      )
    end

    it "keeps compact and root-qualified constant paths as written" do
      scopes = scopes_for(<<~RUBY)
        class Outer::Inner
          def value = 1
        end
        module Wrap
          class ::Top
            def value = 2
          end
        end
      RUBY

      expect(scopes.values).to eq([["class Outer::Inner"], ["module Wrap", "class ::Top"]])
    end

    it "reopens the singleton class of a constant" do
      scopes = scopes_for(<<~RUBY)
        class Holder
          class << OBJECT
            def value = 1
          end
        end
      RUBY

      expect(scopes).to eq("Holder::OBJECT.value" => ["class Holder", "class << OBJECT"])
    end

    it "evaluates methods of a constructor block inside class_eval of its constant" do
      scopes = scopes_for(<<~RUBY)
        module Outer
          Point = Struct.new(:x) do
            def len = x
          end
          ::Abs = Data.define(:v) do
            def twice = v * 2
          end
        end
        Outer::Pair = Class.new do
          def first = 1
        end
      RUBY

      expect(scopes).to eq(
        "Outer::Point#len" => ["module Outer", "Point.class_eval do"],
        "Abs#twice" => ["module Outer", "::Abs.class_eval do"],
        "Outer::Pair#first" => ["Outer::Pair.class_eval do"]
      )
    end
  end

  describe "namespace attribution" do
    def expressions_for(source)
      Dir.mktmpdir do |dir|
        path = write_source(dir, "lib/sample.rb", source)
        described_class.new.resolve_from_files([path]).map(&:expression)
      end
    end

    it "does not nest a root-qualified class in the enclosing module" do
      expect(expressions_for(<<~RUBY)).to eq(["Top#value"])
        module Wrap
          class ::Top
            def value = 1
          end
        end
      RUBY
    end

    it "attributes a singleton method to its receiver" do
      expect(expressions_for(<<~RUBY)).to eq(["Outer.own", "Outer::Other.near", "Top.level"])
        module Outer
          def self.own = 1
          def Other.near = 2
        end
        def Top.level = 3
      RUBY
    end

    it "skips singleton methods of non-constant objects" do
      expect(expressions_for(<<~RUBY)).to eq([])
        class Holder
          def config.value = 1
          class << registry
            def entry = 2
          end
        end
      RUBY
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

  it "resolves root-qualified nested namespaces" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          module ::Foo::Bar
            def baz
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects.map(&:expression)).to eq(["Foo::Bar#baz"])
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

  it "ignores anonymous constructor blocks for Module" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            Module.new do
              def hidden = 1
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects).to be_empty
    end
  end

  it "ignores anonymous constructor blocks for Class" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            Class.new do
              def hidden = 1
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects).to be_empty
    end
  end

  it "ignores anonymous constructor blocks for Struct" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            Struct.new(:token) do
              def hidden = 1
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects).to be_empty
    end
  end

  it "ignores anonymous constructor blocks for Data" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            Data.define(:value) do
              def hidden = 1
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects).to be_empty
    end
  end

  it "does not ignore blocks attached to named receivers using new" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            Foo.new do
              def kept = 1
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects.map(&:expression)).to include("Foo#kept")
    end
  end

  it "does not treat arbitrary block calls as define_method" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            aaa(:bar) do
              1
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects).to be_empty
    end
  end

  it "does not treat lexicographically later block calls as define_method" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            zzz(:bar) do
              1
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects).to be_empty
    end
  end

  it "does not resolve define_method on a constant receiver" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            Foo.define_method(:bar) do
              1
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects).to be_empty
    end
  end

  it "does not resolve a self receiver with an earlier method name" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            self.aaa(:bar) do
              1
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects).to be_empty
    end
  end

  it "does not resolve a self receiver with a later method name" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            self.zzz(:bar) do
              1
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects).to be_empty
    end
  end

  it "ignores define_method calls on non-self receivers" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            other.define_method(:bar) do
              1
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects).to be_empty
    end
  end

  it "ignores top-level define_method calls" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          define_method(:bar) do
            1
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects).to be_empty
    end
  end

  it "ignores define_method calls without a literal name" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          class Foo
            define_method do
              1
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])

      expect(subjects).to be_empty
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

  it "does not match a different exact expression" do
    subjects = [
      Henitai::Subject.parse("Foo#baz"),
      Henitai::Subject.parse("Foo.bar"),
      Henitai::Subject.parse("Foo::Bar#qux")
    ]

    filtered = described_class.new.apply_pattern(subjects, "Foo#bar")

    expect(filtered).to be_empty
  end

  it "does not match a lexicographically earlier exact expression" do
    subjects = [
      Henitai::Subject.parse("Foo#aaa"),
      Henitai::Subject.parse("Foo.bar"),
      Henitai::Subject.parse("Foo::Bar#aaa")
    ]

    filtered = described_class.new.apply_pattern(subjects, "Foo#bar")

    expect(filtered).to be_empty
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

  it "applies wildcard patterns to resolved subjects from files" do
    Dir.mktmpdir do |dir|
      path = write_source(
        dir,
        "lib/sample.rb",
        <<~RUBY
          module Foo
            def bar
            end

            module Nested
              def baz
              end
            end
          end

          module Bar
            def qux
            end
          end
        RUBY
      )

      subjects = described_class.new.resolve_from_files([path])
      filtered = described_class.new.apply_pattern(subjects, "Foo*")

      expect(filtered.map(&:expression)).to eq(["Foo#bar", "Foo::Nested#baz"])
    end
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
