# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::AvailableCpuCount do
  describe ".detect" do
    it "returns the smallest positive CPU count from the available sources" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max("400000 100000")
      stub_cpuset_effective("1-6")

      expect(described_class.detect).to eq(4)
    end

    it "falls back to cfs quota files when cpu.max is unavailable" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_cfs("300000", "100000")
      stub_cpuset_missing

      expect(described_class.detect).to eq(3)
    end

    it "falls back to cpuset when cgroup quota data is unavailable" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_cfs(nil, nil)
      stub_cpuset_effective("4-5")

      expect(described_class.detect).to eq(2)
    end

    it "returns one when every source is absent or non-positive" do
      stub_nprocessors(0)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_cfs(nil, nil)
      stub_cpuset_missing

      expect(described_class.detect).to eq(1)
    end
  end

  def stub_nprocessors(count)
    allow(Etc).to receive(:nprocessors).and_return(count)
  end

  def stub_cgroup_cpu_max(value)
    if value.nil?
      allow(File).to receive(:file?).with("/sys/fs/cgroup/cpu.max").and_return(false)
    else
      allow(File).to receive(:file?).with("/sys/fs/cgroup/cpu.max").and_return(true)
      allow(File).to receive(:read).with("/sys/fs/cgroup/cpu.max").and_return(value)
    end
  end

  def stub_cgroup_cfs(quota, period)
    stub_cgroup_file("/sys/fs/cgroup/cpu/cpu.cfs_quota_us", quota)
    stub_cgroup_file("/sys/fs/cgroup/cpu/cpu.cfs_period_us", period)
  end

  def stub_cgroup_file(path, value)
    allow(File).to receive(:file?).with(path).and_return(!value.nil?)
    allow(File).to receive(:read).with(path).and_return(value) unless value.nil?
  end

  def stub_cpuset_effective(value)
    allow(File).to receive(:file?).with("/sys/fs/cgroup/cpuset.cpus.effective").and_return(true)
    allow(File).to receive(:read).with("/sys/fs/cgroup/cpuset.cpus.effective").and_return(value)
  end

  def stub_cpuset_missing
    allow(File).to receive(:file?).with("/sys/fs/cgroup/cpuset.cpus.effective").and_return(false)
    allow(File).to receive(:file?).with("/sys/fs/cgroup/cpuset.cpus").and_return(false)
  end
end
