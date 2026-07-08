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

    it "falls back when cpu.max contains only whitespace" do
      stub_nprocessors(8)
      allow(File).to receive(:file?).with("/sys/fs/cgroup/cpu.max").and_return(true)
      allow(File).to receive(:read).with("/sys/fs/cgroup/cpu.max").and_return("   ")
      stub_cgroup_cfs(nil, nil)
      stub_cpuset_missing

      expect(described_class.detect).to eq(8)
    end

    it "falls back when cpu.max quota is unrestricted max" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max("max 100000")
      stub_cgroup_cfs(nil, nil)
      stub_cpuset_missing

      expect(described_class.detect).to eq(8)
    end

    it "falls back when cfs quota is unrestricted negative one" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_cfs("-1", "100000")
      stub_cpuset_missing

      expect(described_class.detect).to eq(8)
    end

    it "falls back when cfs period file is missing but quota exists" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_file("/sys/fs/cgroup/cpu/cpu.cfs_quota_us", "500000")
      stub_cgroup_file("/sys/fs/cgroup/cpu/cpu.cfs_period_us", nil)
      stub_cpuset_missing

      expect(described_class.detect).to eq(8)
    end

    it "falls back when cfs quota is zero" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_cfs("0", "100000")
      stub_cpuset_missing

      expect(described_class.detect).to eq(8)
    end

    it "falls back when cfs period is zero" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_cfs("100000", "0")
      stub_cpuset_missing

      expect(described_class.detect).to eq(8)
    end

    it "falls back when cfs period is negative" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_cfs("100000", "-100")
      stub_cpuset_missing

      expect(described_class.detect).to eq(8)
    end

    it "falls back when reading a cgroup file raises Errno::EACCES" do
      stub_nprocessors(8)
      allow(File).to receive(:file?).with("/sys/fs/cgroup/cpu.max").and_return(true)
      allow(File).to receive(:read).with("/sys/fs/cgroup/cpu.max").and_raise(Errno::EACCES)
      stub_cgroup_cfs(nil, nil)
      stub_cpuset_missing

      expect(described_class.detect).to eq(8)
    end

    it "falls back to nprocessors when a cpuset entry is not numeric" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_cfs(nil, nil)
      stub_cpuset_effective("abc")
      allow(File).to receive(:file?).with("/sys/fs/cgroup/cpuset.cpus").and_return(false)

      expect(described_class.detect).to eq(8)
    end

    it "falls back when cpuset effective is empty string" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_cfs(nil, nil)
      allow(File).to receive(:file?).with("/sys/fs/cgroup/cpuset.cpus.effective").and_return(true)
      allow(File).to receive(:read).with("/sys/fs/cgroup/cpuset.cpus.effective").and_return("")
      allow(File).to receive(:file?).with("/sys/fs/cgroup/cpuset.cpus").and_return(false)

      expect(described_class.detect).to eq(8)
    end

    it "counts multiple comma-separated cpus from cpuset" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_cfs(nil, nil)
      stub_cpuset_effective("0,2")
      allow(File).to receive(:file?).with("/sys/fs/cgroup/cpuset.cpus").and_return(false)

      expect(described_class.detect).to eq(2)
    end

    it "returns one for single cpuset cpu with no other source" do
      stub_nprocessors(0)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_cfs(nil, nil)
      stub_cpuset_effective("0")
      allow(File).to receive(:file?).with("/sys/fs/cgroup/cpuset.cpus").and_return(false)

      expect(described_class.detect).to eq(1)
    end

    it "uses cpuset range count when it is the only source" do
      stub_nprocessors(0)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_cfs(nil, nil)
      stub_cpuset_effective("0-1")
      allow(File).to receive(:file?).with("/sys/fs/cgroup/cpuset.cpus").and_return(false)

      expect(described_class.detect).to eq(2)
    end

    it "floors sub-one quota ratio to one cpu" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max("150000 100000")
      stub_cpuset_missing

      expect(described_class.detect).to eq(1)
    end

    it "falls back to cpuset.cpus when cpuset.cpus.effective is absent" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_cfs(nil, nil)
      allow(File).to receive(:file?).with("/sys/fs/cgroup/cpuset.cpus.effective").and_return(false)
      allow(File).to receive(:file?).with("/sys/fs/cgroup/cpuset.cpus").and_return(true)
      allow(File).to receive(:read).with("/sys/fs/cgroup/cpuset.cpus").and_return("0-2")

      expect(described_class.detect).to eq(3)
    end

    it "falls back to cpuset.cpus when cpuset.cpus.effective is present but empty" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max(nil)
      stub_cgroup_cfs(nil, nil)
      stub_cpuset_effective("")
      allow(File).to receive(:file?).with("/sys/fs/cgroup/cpuset.cpus").and_return(true)
      allow(File).to receive(:read).with("/sys/fs/cgroup/cpuset.cpus").and_return("0-2")

      expect(described_class.detect).to eq(3)
    end

    it "distinguishes a quota equal to the period from a quota greater than it" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max("100000 100000")
      stub_cpuset_missing

      expect(described_class.detect).to eq(1)
    end

    it "returns the exact quota/period ratio rather than flooring to zero incorrectly" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max("250000 100000")
      stub_cpuset_missing

      expect(described_class.detect).to eq(2)
    end

    it "floors a quota smaller than the period to one cpu, not zero" do
      stub_nprocessors(8)
      stub_cgroup_cpu_max("50000 100000")
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
