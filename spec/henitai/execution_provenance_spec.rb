# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::ExecutionProvenance do
  def write(dir, name, content)
    path = File.join(dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  # Edits a file and moves its mtime forward, as any editor or git checkout
  # does; the content is optionally restored afterwards.
  def touch_later(path, content)
    File.write(path, content)
    later = File.mtime(path) + 5
    File.utime(later, later, path)
  end

  def capture(dir, paths)
    described_class.capture(paths, root: dir)
  end

  it "is intact while captured files are unchanged" do
    Dir.mktmpdir do |dir|
      source = write(dir, "lib/sample.rb", "A = 1\n")

      expect(capture(dir, [source]).intact?([source])).to be(true)
    end
  end

  it "compares expanded paths" do
    Dir.mktmpdir do |dir|
      write(dir, "lib/sample.rb", "A = 1\n")

      Dir.chdir(dir) do
        expect(capture(dir, ["lib/sample.rb"]).intact?([File.join(Dir.pwd, "lib/sample.rb")])).to be(true)
      end
    end
  end

  it "is not intact once a captured file was edited, even if its content was restored" do
    Dir.mktmpdir do |dir|
      source = write(dir, "lib/sample.rb", "A = 1\n")
      provenance = capture(dir, [source])
      touch_later(source, "A = 1\n")

      expect(provenance.intact?([source])).to be(false)
    end
  end

  it "is not intact for a file it never captured" do
    Dir.mktmpdir do |dir|
      source = write(dir, "lib/sample.rb", "A = 1\n")
      provenance = capture(dir, [source])

      expect(provenance.intact?([write(dir, "spec/new_spec.rb", "")])).to be(false)
    end
  end

  it "is not intact for a captured file that has been deleted" do
    Dir.mktmpdir do |dir|
      source = write(dir, "lib/sample.rb", "A = 1\n")
      provenance = capture(dir, [source])
      File.delete(source)

      expect(provenance.intact?([source])).to be(false)
    end
  end

  describe "test dependency files" do
    it "invalidates every path, for good, once a dependency was edited", :aggregate_failures do
      Dir.mktmpdir do |dir|
        source = write(dir, "lib/sample.rb", "A = 1\n")
        helper = write(dir, "spec/spec_helper.rb", "# helper\n")
        provenance = capture(dir, [source])
        touch_later(helper, "# edited\n")

        expect(provenance.intact?([source])).to be(false)
        touch_later(helper, "# helper\n")
        expect(provenance.intact?([source])).to be(false)
      end
    end

    it "invalidates every path once a dependency file appears" do
      Dir.mktmpdir do |dir|
        source = write(dir, "lib/sample.rb", "A = 1\n")
        provenance = capture(dir, [source])
        write(dir, "spec/support/new_helper.rb", "# new\n")

        expect(provenance.intact?([source])).to be(false)
      end
    end

    it "stays intact while dependencies are unchanged" do
      Dir.mktmpdir do |dir|
        source = write(dir, "lib/sample.rb", "A = 1\n")
        write(dir, "spec/spec_helper.rb", "# helper\n")

        expect(capture(dir, [source]).intact?([source])).to be(true)
      end
    end
  end
end
