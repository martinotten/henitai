#!/bin/bash
set -euo pipefail

PI_PROVIDER_ID="${PI_PROVIDER_ID:-host-openai}"
PI_MODELS_FILE="${PI_MODELS_FILE:-$HOME/.pi/agent/models.json}"

mkdir -p "$(dirname "$PI_MODELS_FILE")"

ruby <<'RUBY'
require "json"
require "net/http"
require "uri"

provider_id = ENV.fetch("PI_PROVIDER_ID", "host-openai")
base_url = ENV.fetch("PI_OPENAI_BASE_URL", "http://host.docker.internal:8000/v1")
api_key = ENV.fetch("PI_OPENAI_API_KEY", "llmapi")
models_file = ENV.fetch("PI_MODELS_FILE", File.join(Dir.home, ".pi", "agent", "models.json"))
fallback_model_ids = ENV.fetch("PI_MODEL_IDS", "").split(",").map(&:strip).reject(&:empty?)

def models_endpoint(base_url)
  normalized_base_url = base_url.end_with?("/") ? base_url : "#{base_url}/"
  URI.join(normalized_base_url, "models")
end

def fetch_model_ids(base_url, api_key)
  uri = models_endpoint(base_url)
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{api_key}"

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 3, read_timeout: 10) do |http|
    http.request(request)
  end

  unless response.is_a?(Net::HTTPSuccess)
    warn "Pi model discovery failed: #{response.code} #{response.message}"
    return []
  end

  JSON.parse(response.body).fetch("data", []).filter_map { |model| model["id"] }
rescue StandardError => e
  warn "Pi model discovery failed: #{e.class}: #{e.message}"
  []
end

model_ids = fetch_model_ids(base_url, api_key)
model_ids = fallback_model_ids if model_ids.empty?

if model_ids.empty?
  warn "No Pi models discovered. Start the host server and run configure-pi-models again."
  exit 0
end

config = {
  "providers" => {
    provider_id => {
      "baseUrl" => base_url,
      "api" => "openai-completions",
      "apiKey" => "$PI_OPENAI_API_KEY",
      "compat" => {
        "supportsStore" => false,
        "supportsDeveloperRole" => false,
        "supportsReasoningEffort" => false,
        "supportsUsageInStreaming" => false,
        "supportsStrictMode" => false,
        "maxTokensField" => "max_tokens"
      },
      "models" => model_ids.uniq.map { |id| { "id" => id } }
    }
  }
}

File.write(models_file, "#{JSON.pretty_generate(config)}\n")
puts "Wrote #{models_file} with #{model_ids.uniq.size} Pi model(s) for #{base_url}."
RUBY
