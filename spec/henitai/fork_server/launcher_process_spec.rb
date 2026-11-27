# frozen_string_literal: true

require "spec_helper"
require "socket"
require "stringio"

# Real forks, so this file must be named *_process_spec.rb: bin/verify-process-free-specs
# excludes that pattern and .henitai.yml keeps it out of mutant children.
#
# The process-free half of the launcher's behavior lives in launcher_spec.rb;
# what only a real fork can show is asserted here: the child inherits the
# request's environment, the returned pid really is that child, and its exit
# status is the one the integration's child run produced.
RSpec.describe Henitai::ForkServer::Launcher, :aggregate_failures do
  # A double is not usable across a fork boundary, so the child's work is a
  # plain object answering the one message the production code sends it.
  def integration_reading(writer)
    Object.new.tap do |integration|
      integration.define_singleton_method(:run_in_child) do |mutant:, test_files:, log_paths:|
        Henitai::Integration::CoverageRuntimeSuppressors.suppress_simplecov!
        writer.puts([
          mutant.id, test_files.join(","), log_paths.keys.join(","),
          ENV.fetch("HENITAI_MUTANT_ID", "unset"), ENV.fetch("HENITAI_SPEC_PROBE", "unset")
        ].join("|"))
        writer.flush
        3
      end
    end
  end

  def mutant_input
    Struct.new(:id).new("m1")
  end

  def kill_quietly(pid)
    return unless pid

    Process.kill(:KILL, pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  it "runs the tests in the forked child, with the request's env, and exits with their status" do
    reader, writer = IO.pipe
    integration = integration_reading(writer)
    launcher = described_class.new(integration:, mutants: { "m1" => mutant_input }, socket: StringIO.new)

    pid = launcher.call(
      "mutant_id" => "m1",
      "test_files" => ["a_spec.rb", "b_spec.rb"],
      "log_paths" => { "report_path" => "reports/m1.json", "stdout_path" => "reports/m1.log" },
      "env" => { "HENITAI_SPEC_PROBE" => "from-request" }
    )
    writer.close
    output = reader.read
    status = Process.wait2(pid).last

    expect(output).to eq(
      "m1|a_spec.rb,b_spec.rb|report_path,stdout_path|m1|from-request\n"
    )
    expect(status.exitstatus).to eq(3)
  ensure
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
    kill_quietly(pid)
  end

  it "closes its end of the server connection in the child, so the server sees the fork" do
    sockets = UNIXSocket.pair
    launcher = described_class.new(
      integration: integration_reading(StringIO.new),
      mutants: { "m1" => mutant_input },
      socket: sockets.last
    )

    pid = launcher.call("mutant_id" => "m1", "test_files" => [], "log_paths" => {})
    sockets.last.close

    expect(sockets.first.wait_readable(5)).to be(sockets.first)
    expect(sockets.first.read_nonblock(1, exception: false)).to be_nil
  ensure
    kill_quietly(pid)
    sockets&.each { |socket| socket.close unless socket.closed? }
  end
end
