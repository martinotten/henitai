# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::RegexMetacharacters do
  def scan(source)
    described_class.new(source)
  end

  it "finds quantifiers applied to an atom" do
    expect([scan("a+b*").quantifiers("+"), scan("a+b*").quantifiers("*")]).to eq([[1], [3]])
  end

  it "finds quantifiers applied to a group, a class and an escape" do
    expect(scan("(ab)+[cd]+\\d+").quantifiers("+")).to eq([4, 9, 12])
  end

  it "ignores the second character of a lazy or possessive quantifier" do
    expect([scan("a*+").quantifiers("+"), scan("a+*").quantifiers("*")]).to eq([[], []])
  end

  it "ignores a quantifier that follows an interval" do
    expect(scan("a{2}+").quantifiers("+")).to eq([])
  end

  it "ignores a quantifier character at the start of a group or alternative" do
    expect(scan("(?:a)|*").quantifiers("*")).to eq([])
  end

  it "ignores escaped metacharacters" do
    expect([scan("\\+\\^\\[").quantifiers("+"), scan("\\^").anchors("^"), scan("\\[").class_openers])
      .to eq([[], [], []])
  end

  it "ignores metacharacters inside a character class" do
    expect([scan("[+^$]").quantifiers("+"), scan("[a^]").anchors("^"), scan("[a$]").anchors("$")])
      .to eq([[], [], []])
  end

  it "finds anchors outside character classes" do
    expect([scan("^a|^b$").anchors("^"), scan("^a|^b$").anchors("$")]).to eq([[0, 3], [5]])
  end

  it "does not count a negated class caret as an anchor" do
    expect(scan("[^a]^").anchors("^")).to eq([4])
  end

  it "finds the openers of top-level, non-negated classes" do
    expect(scan("[a][^b][c[d]]").class_openers).to eq([0, 7])
  end

  it "treats a POSIX bracket as part of its class" do
    expect([scan("[[:alpha:]]+").class_openers, scan("[[:alpha:]]+").quantifiers("+")]).to eq([[0], [11]])
  end

  it "resumes scanning after an escaped closing bracket inside a class" do
    expect(scan("[\\]]+").quantifiers("+")).to eq([4])
  end
end
