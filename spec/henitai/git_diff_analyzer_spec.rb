# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::GitDiffAnalyzer do
  def successful_status
    instance_double(Process::Status, success?: true)
  end

  def failed_status
    instance_double(Process::Status, success?: false)
  end

  def write_file(dir, relative_path, source)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  it "raises when git diff fails" do
    allow(Open3).to receive(:capture3).and_return(["", "fatal: missing ref", failed_status])

    expect do
      described_class.new.changed_files(from: "HEAD", to: "missing-ref")
    end.to raise_error(Henitai::GitDiffError, /fatal: missing ref/)
  end

  it "returns nil when git is unavailable" do
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

    expect(described_class.new.head_sha).to be_nil
  end

  it "invokes git to resolve the head SHA" do
    allow(Open3).to receive(:capture3).and_return(["deadbeef\n", "", successful_status])

    described_class.new.head_sha(dir: "/tmp/repo")

    expect(Open3).to have_received(:capture3).with(
      "git", "-C", "/tmp/repo", "rev-parse", "HEAD"
    )
  end

  it "returns the current commit SHA" do
    allow(Open3).to receive(:capture3).and_return(["deadbeef\n", "", successful_status])

    expect(described_class.new.head_sha).to eq("deadbeef")
  end

  it "returns changed files from git output" do
    allow(Open3).to receive(:capture3).and_return(
      ["lib/alpha.rb\nlib/beta.rb\n", "", successful_status]
    )

    expect(described_class.new.changed_files(from: "main", to: "HEAD")).to eq(
      ["lib/alpha.rb", "lib/beta.rb"]
    )
  end

  it "invokes git with the configured directory and refs" do
    allow(Open3).to receive(:capture3).and_return(["lib/alpha.rb\n", "", successful_status])

    described_class.new.changed_files(from: "main", to: "HEAD", dir: "/tmp/repo")

    expect(Open3).to have_received(:capture3).with(
      "git", "-C", "/tmp/repo", "diff", "--name-only", "main", "HEAD"
    )
  end

  it "combines tracked and untracked working-tree files without duplicates" do
    allow(Open3).to receive(:capture3) do |*command|
      if command.include?("diff")
        ["lib/tracked.rb\nlib/shared.rb\n", "", successful_status]
      else
        ["lib/shared.rb\nlib/untracked.rb\n", "", successful_status]
      end
    end

    expect(described_class.new.working_tree_changed_files).to eq(
      ["lib/tracked.rb", "lib/shared.rb", "lib/untracked.rb"]
    )
  end

  it "uses distinct git commands for tracked and untracked files", :aggregate_failures do
    allow(Open3).to receive(:capture3) do |*command|
      if command.include?("ls-files")
        ["lib/untracked.rb\n", "", successful_status]
      else
        ["lib/tracked.rb\n", "", successful_status]
      end
    end

    described_class.new.working_tree_changed_files(dir: "/tmp/repo")

    expect(Open3).to have_received(:capture3).with(
      "git", "-C", "/tmp/repo", "diff", "--name-only", "HEAD"
    )
    expect(Open3).to have_received(:capture3).with(
      "git", "-C", "/tmp/repo", "ls-files", "--others", "--exclude-standard"
    )
  end

  it "returns only methods overlapping changed lines" do
    Dir.mktmpdir do |dir|
      write_file(
        dir,
        "lib/sample.rb",
        "class Sample\n  def alpha = 1\n  def beta = 2\nend\n"
      )
      allow(Open3).to receive(:capture3) do |*command|
        if command.include?("--name-only")
          ["lib/sample.rb\n", "", successful_status]
        else
          ["@@ -2 +2 @@\n", "", successful_status]
        end
      end

      methods = described_class.new.changed_methods(from: "HEAD~1", to: "HEAD", dir:)

      expect(methods.map(&:method_name)).to eq(["alpha"])
    end
  end

  it "uses a zero-context diff for changed method ranges" do
    Dir.mktmpdir do |dir|
      write_file(dir, "lib/sample.rb", "class Sample\n  def alpha = 1\nend\n")
      allow(Open3).to receive(:capture3) do |*command|
        if command.include?("--name-only")
          ["lib/sample.rb\n", "", successful_status]
        else
          ["@@ -2 +2 @@\n", "", successful_status]
        end
      end

      described_class.new.changed_methods(from: "HEAD~1", to: "HEAD", dir:)

      expect(Open3).to have_received(:capture3).with(
        "git", "-C", dir, "diff", "--unified=0", "HEAD~1", "HEAD", "--", "lib/sample.rb"
      )
    end
  end

  it "returns methods across a multi-line changed hunk" do
    Dir.mktmpdir do |dir|
      write_file(
        dir,
        "lib/sample.rb",
        "class Sample\n  def alpha = 1\n  def beta = 2\nend\n"
      )
      allow(Open3).to receive(:capture3) do |*command|
        if command.include?("--name-only")
          ["lib/sample.rb\n", "", successful_status]
        else
          ["@@ -2,2 +2,2 @@\n", "", successful_status]
        end
      end

      methods = described_class.new.changed_methods(from: "HEAD~1", to: "HEAD", dir:)

      expect(methods.map(&:method_name)).to eq(%w[alpha beta])
    end
  end

  it "raises when git diff for changed methods fails" do
    Dir.mktmpdir do |dir|
      write_file(
        dir,
        "lib/sample.rb",
        "class Sample\n  def alpha = 1\nend\n"
      )
      allow(Open3).to receive(:capture3) do |*args|
        if args.include?("--name-only")
          ["lib/sample.rb\n", "", successful_status]
        else
          ["", "fatal: broken diff", failed_status]
        end
      end

      expect do
        described_class.new.changed_methods(from: "HEAD~1", to: "HEAD", dir:)
      end.to raise_error(Henitai::GitDiffError, /fatal: broken diff/)
    end
  end
end
