#!/usr/bin/env bash
set -euo pipefail

# CI validation gate for the api-gateway layer (test-coverage-enforcement
# capability, config/script equivalent). Runs KrakenD config checks on every
# gateway config plus the bootstrap-scope verification script. Any failure
# returns non-zero and blocks the layer gate.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"

krakend_image="${KRAKEND_IMAGE:-krakend:2.13}"

run_krakend() {
  if command -v krakend >/dev/null 2>&1; then
    ( cd "${repo_dir}" && krakend "$@" )
    return
  fi

  docker run --rm \
    -v "${repo_dir}:/etc/krakend" \
    -w /etc/krakend \
    "${krakend_image}" "$@"
}

for config in krakend.json krakend-bootstrap.json krakend-banking.json; do
  config_path="${repo_dir}/${config}"
  if [[ ! -f "${config_path}" ]]; then
    echo "missing gateway config: ${config_path}" >&2
    exit 1
  fi
  echo "checking ${config}"
  run_krakend check -c "${config}" --lint
done

"${script_dir}/verify-bootstrap-scopes.sh"

echo "api-gateway-validate-ok"
