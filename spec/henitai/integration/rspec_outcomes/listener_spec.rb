# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Integration::RspecOutcomes::Listener do
  subject(:listener) { described_class.new(outcomes) }

  let(:outcomes) { Henitai::TestFileOutcomes.new }

  def group_notification(metadata)
    Struct.new(:group).new(Struct.new(:metadata).new(metadata))
  end

  def message_notification(text)
    Struct.new(:message).new(text)
  end

  def summary(count)
    Struct.new(:errors_outside_of_examples_count).new(count)
  end

  def hook_message
    "\nAn error occurred in an `after(:context)` hook.\nFailure/Error: boom"
  end

  def open_group(file)
    listener.example_group_started(group_notification({ absolute_file_path: file }))
  end

  it "attributes an after(:context) hook error to the open group's spec file" do
    open_group("/app/spec/a_spec.rb")
    listener.message(message_notification(hook_message))
    listener.example_group_finished(nil)

    expect(outcomes.outcomes).to eq("/app/spec/a_spec.rb" => "failed")
  end

  it "falls back to the group's relative file path" do
    listener.example_group_started(group_notification({ file_path: "spec/r_spec.rb" }))
    listener.message(message_notification(hook_message))

    expect(outcomes.failed_files).to eq([File.expand_path("spec/r_spec.rb")])
  end

  it "ignores messages that are not hook errors" do
    open_group("/app/spec/a_spec.rb")
    listener.message(message_notification("Run options: include {}"))

    expect(outcomes.outcomes).to be_empty
  end

  it "ignores hook error messages outside any group" do
    listener.message(message_notification(hook_message))

    expect(outcomes.outcomes).to be_empty
  end

  it "stops attributing once the group has finished" do
    open_group("/app/spec/a_spec.rb")
    listener.example_group_finished(nil)
    listener.message(message_notification(hook_message))

    expect(outcomes.outcomes).to be_empty
  end

  it "treats an error outside of examples as unattributed when no file was blamed" do
    listener.dump_summary(summary(1))

    expect(outcomes.unattributed_failures?).to be(true)
  end

  it "does not flag errors that were attributed to a file" do
    open_group("/app/spec/a_spec.rb")
    listener.message(message_notification(hook_message))
    listener.dump_summary(summary(1))

    expect(outcomes.unattributed_failures?).to be(false)
  end

  it "flags only the errors beyond the attributed ones" do
    open_group("/app/spec/a_spec.rb")
    listener.message(message_notification(hook_message))
    listener.dump_summary(summary(2))

    expect(outcomes.unattributed_failures?).to be(true)
  end

  it "stays clean when no error happened outside examples" do
    listener.dump_summary(summary(0))

    expect(outcomes.unattributed_failures?).to be(false)
  end
end
