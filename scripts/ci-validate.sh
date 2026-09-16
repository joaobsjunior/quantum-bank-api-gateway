#!/usr/bin/env bash
set -euo pipefail

# CI validation gate for the api-gateway layer (test-coverage-enforcement
# capability, config/script equivalent). Runs KrakenD config checks on every
# gateway config, validates both post-quantum HAProxy terminator configs
# against freshly generated ML-DSA material, and runs the static policy
# scripts. Any failure returns non-zero and blocks the layer gate.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"

krakend_image="${KRAKEND_IMAGE:-krakend:2.13.4}"
haproxy_image="${HAPROXY_IMAGE:-haproxy:3.2-alpine}"
openssl_image="${QUANTUM_BANK_PQC_OPENSSL_IMAGE:-alpine/openssl:3.5.8}"

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

# HAProxy validates certificate files at config-check time, so generate a
# throwaway ML-DSA chain (root ML-DSA-87, leaves ML-DSA-65) with OpenSSL >= 3.5.
tls_dir="$(mktemp -d "${TMPDIR:-/tmp}/quantum-bank-gateway-tls.XXXXXX")"
trap 'rm -rf "${tls_dir}"' EXIT
chmod 755 "${tls_dir}"
cat > "${tls_dir}/gen.sh" <<'GEN'
set -eu
cd "$1"
openssl genpkey -algorithm ML-DSA-87 -out root.key
openssl req -x509 -new -key root.key -days 1 -out ca-chain.crt -subj "/CN=ci-root" \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign"
for leaf in gateway-server gateway-client; do
  openssl genpkey -algorithm ML-DSA-65 -out "${leaf}.key"
  openssl req -new -key "${leaf}.key" -out "${leaf}.csr" -subj "/CN=${leaf}"
  openssl x509 -req -in "${leaf}.csr" -CA ca-chain.crt -CAkey root.key -CAcreateserial -days 1 -out "${leaf}.crt"
  cat "${leaf}.crt" "${leaf}.key" > "${leaf}.pem"
done
GEN
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "${tls_dir}:${tls_dir}" -w "${tls_dir}" --entrypoint sh \
  "${openssl_image}" "${tls_dir}/gen.sh" "${tls_dir}" >/dev/null

for cfg in haproxy-bootstrap.cfg haproxy-banking.cfg; do
  echo "checking tls/${cfg}"
  docker run --rm \
    -v "${repo_dir}/tls:/usr/local/etc/haproxy:ro" \
    -v "${tls_dir}:/etc/quantum-bank/tls:ro" \
    "${haproxy_image}" haproxy -c -f "/usr/local/etc/haproxy/${cfg}"
done

"${script_dir}/verify-bootstrap-scopes.sh"
"${script_dir}/verify-pqc-gateway.sh"

echo "api-gateway-validate-ok"
