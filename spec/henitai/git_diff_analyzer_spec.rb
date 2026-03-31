# frozen_string_literal: true

require "fileutils"
require "open3"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::GitDiffAnalyzer do
  def git(dir, ...)
    Open3.capture3("git", "-C", dir, ...)
  end

  def git!(dir, ...)
    stdout, stderr, status = git(dir, ...)
    return stdout if status.success?

    raise [stdout, stderr].reject(&:empty?).join("\n")
  end

  def configure_git_identity(dir)
    git!(dir, "config", "user.email", "tester@example.com")
    git!(dir, "config", "user.name", "Tester")
  end

  def write_file(dir, relative_path, source)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  def commit_all(dir, message)
    git!(dir, "add", ".")
    git!(dir, "commit", "-m", message)
    git!(dir, "rev-parse", "HEAD").strip
  end

  it "returns changed files between two refs" do
    Dir.mktmpdir do |dir|
      git!(dir, "init")
      configure_git_identity(dir)

      write_file(dir, "lib/sample.rb", "class Sample; end\n")
      commit_all(dir, "Initial commit")

      write_file(dir, "lib/sample.rb", "class Sample\n  def answer = 42\nend\n")
      commit_all(dir, "Update sample")

      changed_files = Dir.chdir(dir) do
        described_class.new.changed_files(from: "HEAD~1", to: "HEAD")
      end

      expect(changed_files).to eq(["lib/sample.rb"])
    end
  end

  it "returns an empty array when no files changed" do
    Dir.mktmpdir do |dir|
      git!(dir, "init")
      configure_git_identity(dir)

      write_file(dir, "lib/sample.rb", "class Sample; end\n")
      commit_all(dir, "Initial commit")

      changed_files = Dir.chdir(dir) do
        described_class.new.changed_files(from: "HEAD", to: "HEAD")
      end

      expect(changed_files).to eq([])
    end
  end

  it "raises when git diff fails" do
    Dir.mktmpdir do |dir|
      git!(dir, "init")
      configure_git_identity(dir)

      write_file(dir, "lib/sample.rb", "class Sample; end\n")
      commit_all(dir, "Initial commit")

      expect do
        Dir.chdir(dir) do
          described_class.new.changed_files(from: "HEAD", to: "missing-ref")
        end
      end.to raise_error(RuntimeError, /fatal/i)
    end
  end
end
