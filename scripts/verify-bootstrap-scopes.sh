#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"

for config in krakend-bootstrap.json krakend.json; do
  config_path="${repo_dir}/${config}"
  if [[ ! -f "${config_path}" ]]; then
    echo "missing gateway config: ${config_path}" >&2
    exit 1
  fi

  ruby -rjson - "${config_path}" <<'RUBY'
config = JSON.parse(File.read(ARGV.fetch(0)))
bootstrap_endpoints = config.fetch('endpoints').select { |endpoint| ['/auth/otk', '/auth/csr'].include?(endpoint.fetch('endpoint')) }
abort 'bootstrap gateway config must define /auth/otk and /auth/csr' unless bootstrap_endpoints.size == 2

bootstrap_endpoints.each do |endpoint|
  validator = endpoint.fetch('extra_config').fetch('auth/validator')
  scopes = validator.fetch('scopes')
  unless scopes == ['profile:read']
    abort "#{endpoint.fetch('endpoint')} must require only profile:read for local mobile bootstrap tokens, got #{scopes.inspect}"
  end
end
RUBY
done

echo "bootstrap-scopes-ok"
