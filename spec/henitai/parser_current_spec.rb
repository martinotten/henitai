# frozen_string_literal: true

require "spec_helper"

# Loader file with no describable class; mirrors the spec/infra convention.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Current Ruby parser loader" do
  it "loads cleanly without leaking parser's version warning to stderr" do
    expect { require "henitai/parser_current" }.not_to output.to_stderr
  end

  it "makes the current Ruby parser available after loading" do
    require "henitai/parser_current"

    expect(defined?(Parser::CurrentRuby)).to eq("constant")
  end
end
# rubocop:enable RSpec/DescribeClass
