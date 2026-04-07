# frozen_string_literal: true

require "spec_helper"
require "henitai/configuration_validator"

RSpec.describe Henitai::ConfigurationValidator do
  def expect_warning(message_pattern = nil)
    allow(described_class).to receive(:warn)

    yield

    matcher = have_received(:warn).at_least(:once)
    matcher = matcher.with(message_pattern) if message_pattern
    expect(described_class).to matcher
  end

  # ---------------------------------------------------------------------------
  # validate!
  # ---------------------------------------------------------------------------
  describe ".validate!" do
    # Muster A: Regex muss den *Pfad* "configuration" matchen, nicht nur das
    # Wort im Boilerplate ("Invalid configuration value for …").
    it "rejects a non-hash root configuration with the path in the error" do
      expect { described_class.validate!([]) }.to raise_error(
        Henitai::ConfigurationError,
        /for configuration:/
      )
    end

    it "accepts an empty hash without error" do
      expect { described_class.validate!({}) }.not_to raise_error
    end

    # Muster C: validate_top_level_keys delegiert an warn_unknown_keys.
    # Wird der Aufruf durch → 0 ersetzt, erscheint keine Warnung.
    it "warns about unknown top-level keys via validate!" do
      expect_warning(/totally_unknown/) do
        described_class.validate!({ totally_unknown: true })
      end
    end
  end

  # ---------------------------------------------------------------------------
  # integration
  # ---------------------------------------------------------------------------
  describe "integration validation" do
    # Muster B: nil-Guard
    it "accepts absent integration" do
      expect { described_class.validate!({}) }.not_to raise_error
    end

    # Muster B: String-Guard
    it "accepts a shorthand string integration" do
      expect { described_class.validate!({ integration: "github_actions" }) }.not_to raise_error
    end

    it "accepts a valid hash integration" do
      expect { described_class.validate!({ integration: { name: "github_actions" } }) }.not_to raise_error
    end

    # Muster A: Pfad "integration" im Fehlertext
    it "rejects a non-hash non-string integration with path in error" do
      expect { described_class.validate!({ integration: 42 }) }.to raise_error(
        Henitai::ConfigurationError, /for integration:/
      )
    end

    # Muster C: warn_unknown_keys mit Pfad "integration" delegiert
    it "warns about unknown integration sub-keys with full path" do
      expect_warning(/integration\.typo_key/) do
        described_class.validate!({ integration: { typo_key: true } })
      end
    end

    # Muster A: Pfad "integration.name"
    it "rejects a non-string integration name with path in error" do
      expect { described_class.validate!({ integration: { name: 42 } }) }.to raise_error(
        Henitai::ConfigurationError, /for integration\.name:/
      )
    end
  end

  # ---------------------------------------------------------------------------
  # includes
  # ---------------------------------------------------------------------------
  describe "includes validation" do
    it "accepts absent includes" do
      expect { described_class.validate!({}) }.not_to raise_error
    end

    it "accepts a string-array includes" do
      expect { described_class.validate!({ includes: ["lib/", "app/"] }) }.not_to raise_error
    end

    # Muster A: Pfad "includes"
    it "rejects a non-array includes with path in error" do
      expect { described_class.validate!({ includes: "lib" }) }.to raise_error(
        Henitai::ConfigurationError, /for includes:/
      )
    end
  end

  # ---------------------------------------------------------------------------
  # jobs
  # ---------------------------------------------------------------------------
  describe "jobs validation" do
    # Muster B: nil-Guard
    it "accepts absent jobs" do
      expect { described_class.validate!({}) }.not_to raise_error
    end

    # Muster B: Integer-Guard
    it "accepts an integer jobs value" do
      expect { described_class.validate!({ jobs: 4 }) }.not_to raise_error
    end

    # Muster A: Interpolation im Fehlertext (got #{value.class})
    it "rejects a non-integer jobs value with path in error" do
      expect { described_class.validate!({ jobs: "4" }) }.to raise_error(
        Henitai::ConfigurationError, /for jobs:.*got String/
      )
    end
  end

  # ---------------------------------------------------------------------------
  # reporters
  # ---------------------------------------------------------------------------
  describe "reporters validation" do
    it "accepts absent reporters" do
      expect { described_class.validate!({}) }.not_to raise_error
    end

    it "accepts a string-array reporters value" do
      expect { described_class.validate!({ reporters: %w[json html] }) }.not_to raise_error
    end

    # Muster A: Pfad "reporters"
    it "rejects a non-array reporters value with path in error" do
      expect { described_class.validate!({ reporters: "json" }) }.to raise_error(
        Henitai::ConfigurationError, /for reporters:/
      )
    end
  end

  # ---------------------------------------------------------------------------
  # all_logs
  # ---------------------------------------------------------------------------
  describe "all_logs validation" do
    it "accepts absent all_logs" do
      expect { described_class.validate!({}) }.not_to raise_error
    end

    it "accepts a boolean all_logs value" do
      expect { described_class.validate!({ all_logs: true }) }.not_to raise_error
    end

    it "rejects a non-boolean all_logs value with path in error" do
      expect { described_class.validate!({ all_logs: "yes" }) }.to raise_error(
        Henitai::ConfigurationError,
        'Invalid configuration value for all_logs: expected true or false, got "yes"'
      )
    end
  end

  # ---------------------------------------------------------------------------
  # reports_dir
  # ---------------------------------------------------------------------------
  describe "reports_dir validation" do
    it "accepts absent reports_dir" do
      expect { described_class.validate!({}) }.not_to raise_error
    end

    it "accepts a string reports_dir" do
      expect { described_class.validate!({ reports_dir: "coverage/" }) }.not_to raise_error
    end

    # Muster A: Pfad "reports_dir"
    it "rejects a non-string reports_dir with path in error" do
      expect { described_class.validate!({ reports_dir: 42 }) }.to raise_error(
        Henitai::ConfigurationError, /for reports_dir:/
      )
    end
  end

  # ---------------------------------------------------------------------------
  # dashboard
  # ---------------------------------------------------------------------------
  describe "dashboard validation" do
    # Muster B: nil-Guard
    it "accepts absent dashboard" do
      expect { described_class.validate!({}) }.not_to raise_error
    end

    # Muster A: Pfad "dashboard" in ensure_hash!
    it "rejects a non-hash dashboard with path in error" do
      expect { described_class.validate!({ dashboard: "https://example.com" }) }.to raise_error(
        Henitai::ConfigurationError, /for dashboard:/
      )
    end

    # Muster C: warn_unknown_keys mit Pfad "dashboard" delegiert
    it "warns about unknown dashboard keys with full path" do
      expect_warning(/dashboard\.typo_key/) do
        described_class.validate!({ dashboard: { typo_key: true } })
      end
    end

    # Muster A: Pfad "dashboard.project"
    it "rejects a non-string dashboard project with path in error" do
      expect { described_class.validate!({ dashboard: { project: 42 } }) }.to raise_error(
        Henitai::ConfigurationError, /for dashboard\.project:/
      )
    end

    # Muster A: Pfad "dashboard.base_url"
    it "rejects a non-string dashboard base_url with path in error" do
      expect { described_class.validate!({ dashboard: { base_url: 42 } }) }.to raise_error(
        Henitai::ConfigurationError, /for dashboard\.base_url:/
      )
    end
  end

  # ---------------------------------------------------------------------------
  # mutation
  # ---------------------------------------------------------------------------
  describe "mutation validation" do
    # Muster B: nil-Guard
    it "accepts absent mutation" do
      expect { described_class.validate!({}) }.not_to raise_error
    end

    # Muster A: Pfad "mutation" in ensure_hash!
    it "rejects a non-hash mutation with path in error" do
      expect { described_class.validate!({ mutation: "all" }) }.to raise_error(
        Henitai::ConfigurationError, /for mutation:/
      )
    end

    # Muster C: warn_unknown_keys mit Pfad "mutation"
    it "warns about unknown mutation keys with full path" do
      expect_warning(/mutation\.typo_key/) do
        described_class.validate!({ mutation: { typo_key: true } })
      end
    end

    it "rejects non-string ignore patterns with the full path in error" do
      expect do
        described_class.validate!({ mutation: { ignore_patterns: ["(send _ :puts _)", 1] } })
      end.to raise_error(
        Henitai::ConfigurationError,
        /mutation\.ignore_patterns: expected Array<String>, got Array<String, Integer>/
      )
    end

    # Muster C: validate_sampling(value[:sampling]) → 0
    it "validates sampling when present (delegated call not skipped)" do
      expect do
        described_class.validate!({ mutation: { sampling: { ratio: 0.5 } } })
      end.to raise_error(Henitai::ConfigurationError, /mutation\.sampling/)
    end

    # Muster C: validate_max_flaky_retries(…) → 0
    it "validates max_flaky_retries when present (delegated call not skipped)" do
      expect do
        described_class.validate!({ mutation: { max_flaky_retries: "bad" } })
      end.to raise_error(Henitai::ConfigurationError, /max_flaky_retries/)
    end

    # Muster C: validate_ignore_patterns(…) → 0
    it "validates ignore_patterns when present (delegated call not skipped)" do
      expect do
        described_class.validate!({ mutation: { ignore_patterns: ["[invalid_regex"] } })
      end.to raise_error(Henitai::ConfigurationError, /mutation\.ignore_patterns/)
    end
  end

  # ---------------------------------------------------------------------------
  # coverage_criteria
  # ---------------------------------------------------------------------------
  describe "coverage_criteria validation" do
    # Muster B: nil-Guard
    it "accepts absent coverage_criteria" do
      expect { described_class.validate!({}) }.not_to raise_error
    end

    # Muster A: Pfad "coverage_criteria" in ensure_hash!
    it "rejects a non-hash coverage_criteria with path in error" do
      expect { described_class.validate!({ coverage_criteria: true }) }.to raise_error(
        Henitai::ConfigurationError, /for coverage_criteria:/
      )
    end

    # Muster C: warn_unknown_keys mit Pfad "coverage_criteria"
    it "warns about unknown coverage_criteria keys with full path" do
      expect_warning(/coverage_criteria\.typo_key/) do
        described_class.validate!({ coverage_criteria: { typo_key: true } })
      end
    end

    # Muster A: Interpolation "coverage_criteria.#{key}" im Fehlertext
    it "rejects a non-boolean coverage_criteria flag with key path in error" do
      expect do
        described_class.validate!({ coverage_criteria: { test_result: "yes" } })
      end.to raise_error(Henitai::ConfigurationError, /for coverage_criteria\.test_result:/)
    end
  end

  # ---------------------------------------------------------------------------
  # thresholds
  # ---------------------------------------------------------------------------
  describe "thresholds validation" do
    # Muster B: nil-Guard
    it "accepts absent thresholds" do
      expect { described_class.validate!({}) }.not_to raise_error
    end

    # Muster A: Pfad "thresholds" in ensure_hash!
    it "rejects a non-hash thresholds with path in error" do
      expect { described_class.validate!({ thresholds: 80 }) }.to raise_error(
        Henitai::ConfigurationError, /for thresholds:/
      )
    end

    # Muster C: warn_unknown_keys mit Pfad "thresholds"
    it "warns about unknown thresholds keys with full path" do
      expect_warning(/thresholds\.typo_key/) do
        described_class.validate!({ thresholds: { typo_key: 80 } })
      end
    end

    # Muster A: Interpolation "thresholds.#{key}"
    it "rejects an out-of-range threshold with key path in error" do
      expect do
        described_class.validate!({ thresholds: { high: 150 } })
      end.to raise_error(Henitai::ConfigurationError, /for thresholds\.high:/)
    end

    it "rejects a non-integer threshold with key path in error" do
      expect do
        described_class.validate!({ thresholds: { low: "80" } })
      end.to raise_error(Henitai::ConfigurationError, /for thresholds\.low:/)
    end
  end

  # ---------------------------------------------------------------------------
  # Mutation validation through validate!
  # ---------------------------------------------------------------------------

  describe "sampling validation" do
    it "requires ratio to be paired with strategy" do
      expect do
        described_class.validate!({ mutation: { sampling: { ratio: 0.5 } } })
      end.to raise_error(Henitai::ConfigurationError, /mutation\.sampling/)
    end

    it "requires strategy to be paired with ratio" do
      expect do
        described_class.validate!({ mutation: { sampling: { strategy: "stratified" } } })
      end.to raise_error(Henitai::ConfigurationError, /mutation\.sampling/)
    end

    it "rejects an out-of-range ratio" do
      expect do
        described_class.validate!({ mutation: { sampling: { ratio: 1.5, strategy: "stratified" } } })
      end.to raise_error(Henitai::ConfigurationError, /mutation\.sampling\.ratio/)
    end

    it "rejects an unknown strategy" do
      expect do
        described_class.validate!({ mutation: { sampling: { ratio: 0.5, strategy: "random" } } })
      end.to raise_error(Henitai::ConfigurationError, /mutation\.sampling\.strategy/)
    end

    it "accepts a valid ratio + strategy pair" do
      expect do
        described_class.validate!({ mutation: { sampling: { ratio: 0.5, strategy: "stratified" } } })
      end.not_to raise_error
    end

    it "accepts nil sampling" do
      expect { described_class.validate!({ mutation: { sampling: nil } }) }.not_to raise_error
    end
  end

  describe "unknown key warnings" do
    it "includes the top-level key name" do
      expect_warning("Unknown configuration key: unknown_top_level") do
        described_class.validate!({ unknown_top_level: true })
      end
    end

    it "includes the nested key path" do
      expect_warning("Unknown configuration key: mutation.unknown_flag") do
        described_class.validate!({ mutation: { unknown_flag: true } })
      end
    end
  end

  describe "string array validation" do
    it "describes a non-array value precisely" do
      expect do
        described_class.validate!({ includes: "lib" })
      end.to raise_error(
        Henitai::ConfigurationError,
        /includes: expected Array<String>, got String/
      )
    end

    it "describes mixed array element types precisely" do
      expect do
        described_class.validate!(
          { mutation: { ignore_patterns: ["(send _ :puts _)", 1] } }
        )
      end.to raise_error(
        Henitai::ConfigurationError,
        /mutation\.ignore_patterns: expected Array<String>, got Array<String, Integer>/
      )
    end
  end

  describe "validate_operator" do
    it "accepts nil" do
      expect { described_class.validate!({ mutation: { operators: nil } }) }.not_to raise_error
    end

    it "accepts :light and :full" do
      %w[light full].each do |op|
        expect { described_class.validate!({ mutation: { operators: op } }) }.not_to raise_error
      end
    end

    it "rejects an unknown operator with path in error" do
      expect { described_class.validate!({ mutation: { operators: "heavy" } }) }.to raise_error(
        Henitai::ConfigurationError, /mutation\.operators/
      )
    end

    it "reports the rejected operator value in the error message" do
      expect { described_class.validate!({ mutation: { operators: "heavy" } }) }.to raise_error(
        Henitai::ConfigurationError,
        "Invalid configuration value for mutation.operators: expected one of light, full, got \"heavy\""
      )
    end
  end

  describe "validate_timeout" do
    it "accepts nil" do
      expect { described_class.validate!({ mutation: { timeout: nil } }) }.not_to raise_error
    end

    it "accepts a numeric value" do
      expect { described_class.validate!({ mutation: { timeout: 30 } }) }.not_to raise_error
    end

    it "rejects a non-numeric timeout with path in error" do
      expect { described_class.validate!({ mutation: { timeout: "30s" } }) }.to raise_error(
        Henitai::ConfigurationError,
        "Invalid configuration value for mutation.timeout: expected Numeric, got String"
      )
    end
  end

  describe "validate_max_mutants_per_line" do
    it "accepts nil" do
      expect do
        described_class.validate!({ mutation: { max_mutants_per_line: nil } })
      end.not_to raise_error
    end

    it "accepts a positive integer" do
      expect do
        described_class.validate!({ mutation: { max_mutants_per_line: 5 } })
      end.not_to raise_error
    end

    it "rejects zero with path in error" do
      expect { described_class.validate!({ mutation: { max_mutants_per_line: 0 } }) }.to raise_error(
        Henitai::ConfigurationError, /mutation\.max_mutants_per_line/
      )
    end

    it "reports the rejected mutant limit value in the error message" do
      expect { described_class.validate!({ mutation: { max_mutants_per_line: 0 } }) }.to raise_error(
        Henitai::ConfigurationError,
        "Invalid configuration value for mutation.max_mutants_per_line: expected Integer >= 1, got 0"
      )
    end

    it "rejects a non-integer with path in error" do
      expect do
        described_class.validate!({ mutation: { max_mutants_per_line: "5" } })
      end.to raise_error(Henitai::ConfigurationError, /mutation\.max_mutants_per_line/)
    end
  end

  describe "validate_max_flaky_retries" do
    it "accepts nil" do
      expect do
        described_class.validate!({ mutation: { max_flaky_retries: nil } })
      end.not_to raise_error
    end

    it "accepts zero" do
      expect { described_class.validate!({ mutation: { max_flaky_retries: 0 } }) }.not_to raise_error
    end

    it "accepts a positive integer" do
      expect { described_class.validate!({ mutation: { max_flaky_retries: 3 } }) }.not_to raise_error
    end

    it "rejects a non-integer with path in error" do
      expect { described_class.validate!({ mutation: { max_flaky_retries: "3" } }) }.to raise_error(
        Henitai::ConfigurationError, /mutation\.max_flaky_retries/
      )
    end

    it "rejects a negative integer with path in error" do
      expect { described_class.validate!({ mutation: { max_flaky_retries: -1 } }) }.to raise_error(
        Henitai::ConfigurationError, /mutation\.max_flaky_retries/
      )
    end

    it "reports the rejected retry budget in the error message" do
      expect { described_class.validate!({ mutation: { max_flaky_retries: -1 } }) }.to raise_error(
        Henitai::ConfigurationError,
        "Invalid configuration value for mutation.max_flaky_retries: expected Integer >= 0, got -1"
      )
    end
  end

  describe "validate_threshold" do
    it "accepts 0" do
      expect { described_class.validate!({ thresholds: { low: 0 } }) }.not_to raise_error
    end

    it "accepts 100" do
      expect { described_class.validate!({ thresholds: { high: 100 } }) }.not_to raise_error
    end

    it "rejects a value above 100 with path in error" do
      expect { described_class.validate!({ thresholds: { high: 101 } }) }.to raise_error(
        Henitai::ConfigurationError, /for thresholds\.high:/
      )
    end

    it "rejects a non-integer with path in error" do
      expect { described_class.validate!({ thresholds: { low: "90" } }) }.to raise_error(
        Henitai::ConfigurationError, /for thresholds\.low:/
      )
    end
  end

  describe "validate_boolean" do
    it "accepts true" do
      expect { described_class.validate!({ coverage_criteria: { test_result: true } }) }.not_to raise_error
    end

    it "accepts false" do
      expect { described_class.validate!({ coverage_criteria: { process_abort: false } }) }.not_to raise_error
    end

    it "rejects a non-boolean with path in error" do
      expect do
        described_class.validate!({ coverage_criteria: { test_result: "yes" } })
      end.to raise_error(Henitai::ConfigurationError, /for coverage_criteria\.test_result:/)
    end
  end

  describe "validate_ignore_patterns" do
    it "reports the invalid pattern and regexp error message" do
      allow(Regexp).to receive(:new).and_raise(RegexpError, "missing ]")
      message = <<~MESSAGE.strip
        Invalid configuration value for mutation.ignore_patterns: invalid regular expression "[invalid_regex": missing ]
      MESSAGE

      expect do
        described_class.validate!({ mutation: { ignore_patterns: ["[invalid_regex"] } })
      end.to raise_error(
        Henitai::ConfigurationError,
        message
      )
    end
  end

  describe "validate_sampling_ratio" do
    it "reports the rejected ratio value in the error message" do
      expect do
        described_class.validate!({ mutation: { sampling: { ratio: 1.5, strategy: "stratified" } } })
      end.to raise_error(
        Henitai::ConfigurationError,
        "Invalid configuration value for mutation.sampling.ratio: expected Numeric between 0 and 1, got 1.5"
      )
    end
  end

  describe "validate_sampling_strategy" do
    it "reports the rejected strategy value in the error message" do
      expect do
        described_class.validate!({ mutation: { sampling: { ratio: 0.5, strategy: "random" } } })
      end.to raise_error(
        Henitai::ConfigurationError,
        'Invalid configuration value for mutation.sampling.strategy: expected stratified, got "random"'
      )
    end
  end

  describe "validate_optional_string" do
    it "accepts nil" do
      expect { described_class.validate!({ reports_dir: nil }) }.not_to raise_error
    end

    it "accepts a string" do
      expect { described_class.validate!({ reports_dir: "coverage/" }) }.not_to raise_error
    end

    it "rejects a non-string non-nil value with path in error" do
      expect { described_class.validate!({ reports_dir: 42 }) }.to raise_error(
        Henitai::ConfigurationError, /for reports_dir:/
      )
    end
  end

  describe "ensure_hash!" do
    it "accepts a hash" do
      expect { described_class.validate!({ dashboard: {} }) }.not_to raise_error
    end

    it "rejects a non-hash with the path in the error" do
      expect { described_class.validate!({ dashboard: "string" }) }.to raise_error(
        Henitai::ConfigurationError, /for dashboard:/
      )
    end
  end
end
