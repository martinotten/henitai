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
end
