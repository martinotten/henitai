# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Integration::RspecFileOrder do
  let(:group_struct) { Struct.new(:metadata) }

  def group(file, name)
    group_struct.new({ absolute_file_path: File.expand_path(file), description: name })
  end

  def names(groups)
    groups.map { |g| g.metadata.fetch(:description) }
  end

  it "orders groups by the position of their file in the list" do
    groups = [group("/x/b_spec.rb", "b"), group("/x/a_spec.rb", "a")]

    sorted = described_class.new(["/x/a_spec.rb", "/x/b_spec.rb"]).sort(groups)

    expect(names(sorted)).to eq(%w[a b])
  end

  it "keeps the input order of groups from the same file" do
    groups = [group("/x/b_spec.rb", "b1"), group("/x/a_spec.rb", "a1"), group("/x/a_spec.rb", "a2")]

    sorted = described_class.new(["/x/a_spec.rb", "/x/b_spec.rb"]).sort(groups)

    expect(names(sorted)).to eq(%w[a1 a2 b1])
  end

  it "puts groups from unlisted files last, in their input order" do
    groups = [group("/x/z_spec.rb", "z"), group("/x/b_spec.rb", "b"), group("/x/y_spec.rb", "y")]

    sorted = described_class.new(["/x/b_spec.rb"]).sort(groups)

    expect(names(sorted)).to eq(%w[b z y])
  end

  it "matches relative paths in the list against absolute group files" do
    groups = [group("spec/b_spec.rb", "b"), group("spec/a_spec.rb", "a")]

    sorted = described_class.new(["spec/a_spec.rb", "spec/b_spec.rb"]).sort(groups)

    expect(names(sorted)).to eq(%w[a b])
  end

  it "resolves a group file from file_path when absolute_file_path is missing" do
    relative = group_struct.new({ file_path: "./spec/only_spec.rb", description: "only" })

    expect(described_class.file_of(relative)).to eq(File.expand_path("./spec/only_spec.rb"))
  end
end
