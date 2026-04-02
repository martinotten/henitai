# frozen_string_literal: true

# rubocop:disable RSpec/SpecFilePathFormat

require "spec_helper"

RSpec.describe SimpleCov::Formatter::QuietHTMLFormatter do
  it "suppresses the formatter output" do
    result = instance_double(SimpleCov::Result)
    formatter = described_class.new
    html_formatter = instance_double(SimpleCov::Formatter::HTMLFormatter)

    allow(SimpleCov::Formatter::HTMLFormatter).to receive(:new).and_return(html_formatter)
    allow(html_formatter).to receive(:format) do
      $stdout.puts "Coverage report generated for RSpec to /workspaces/henitai/coverage."
    end

    expect { formatter.format(result) }.not_to output.to_stdout
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
