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

  python3 - "${config_path}" <<'PY'
import json, sys
config = json.load(open(sys.argv[1]))
bootstrap_endpoints = [e for e in config["endpoints"] if e["endpoint"] in ("/auth/otk", "/auth/csr")]
if len(bootstrap_endpoints) != 2:
    sys.exit("bootstrap gateway config must define /auth/otk and /auth/csr")
for endpoint in bootstrap_endpoints:
    scopes = endpoint["extra_config"]["auth/validator"]["scopes"]
    if scopes != ["profile:read"]:
        sys.exit(f"{endpoint['endpoint']} must require only profile:read for local mobile bootstrap tokens, got {scopes!r}")
PY
done

echo "bootstrap-scopes-ok"
