#!/usr/bin/env bash
set -euo pipefail

# Static post-quantum transport policy for the gateway layer.
#
# - KrakenD never terminates TLS (Go crypto/tls has no ML-DSA): it binds to
#   127.0.0.1 only, carries no `tls`/`client_tls` blocks, and every backend or
#   JWKS URL it reaches is a loopback HAProxy egress.
# - Each HAProxy terminator is TLS 1.3 only, negotiates X25519MLKEM768 only,
#   accepts/produces ML-DSA-65/87 signature schemes only, and the banking
#   listener requires a client certificate that chains to the local PKI.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"

fail() {
  echo "$*" >&2
  exit 1
}

for config in krakend.json krakend-bootstrap.json krakend-banking.json; do
  config_path="${repo_dir}/${config}"
  [[ -f "${config_path}" ]] || fail "missing gateway config: ${config_path}"
  python3 - "${config_path}" <<'PY'
import json, sys
path = sys.argv[1]
cfg = json.load(open(path))
def fail(msg):
    sys.exit(f"{path}: {msg}")
if cfg.get("listen_ip") != "127.0.0.1":
    fail("KrakenD must listen on 127.0.0.1 only; the HAProxy terminator owns the public socket")
for forbidden in ("tls", "client_tls"):
    if forbidden in cfg:
        fail(f"KrakenD must not configure '{forbidden}': TLS is post-quantum and terminated by HAProxy")
for ep in cfg.get("endpoints", []):
    for backend in ep.get("backend", []):
        for host in backend.get("host", []):
            if not host.startswith("http://127.0.0.1:"):
                fail(f"{ep['endpoint']} backend host {host!r} must be the loopback HAProxy egress")
    validator = ep.get("extra_config", {}).get("auth/validator")
    if validator is None:
        fail(f"{ep['endpoint']} has no auth/validator")
    jwk = validator.get("jwk_url", "")
    if not jwk.startswith("http://127.0.0.1:"):
        fail(f"{ep['endpoint']} jwk_url {jwk!r} must be the loopback HAProxy issuer egress")
    if validator.get("disable_jwk_security") is not True:
        fail(f"{ep['endpoint']} loopback JWKS egress requires disable_jwk_security=true (https is enforced by HAProxy)")
    if not validator.get("issuer", "").startswith("https://"):
        fail(f"{ep['endpoint']} issuer must be an https origin")
    if "jwk_local_ca" in validator:
        fail(f"{ep['endpoint']} must not carry jwk_local_ca (KrakenD cannot verify ML-DSA anchors)")
PY
done

require_line() {
  local file="$1"
  local pattern="$2"
  grep -Eq -- "${pattern}" "${file}" || fail "${file}: missing required setting matching /${pattern}/"
}

forbid_line() {
  local file="$1"
  local pattern="$2"
  if grep -Eq -- "${pattern}" "${file}"; then
    fail "${file}: forbidden setting matching /${pattern}/"
  fi
}

for cfg in haproxy-bootstrap.cfg haproxy-banking.cfg; do
  file="${repo_dir}/tls/${cfg}"
  [[ -f "${file}" ]] || fail "missing terminator config: ${file}"
  require_line "${file}" '^\s*ssl-default-bind-options .*ssl-min-ver TLSv1\.3 ssl-max-ver TLSv1\.3'
  require_line "${file}" '^\s*ssl-default-server-options .*ssl-min-ver TLSv1\.3 ssl-max-ver TLSv1\.3'
  require_line "${file}" '^\s*ssl-default-bind-curves X25519MLKEM768$'
  require_line "${file}" '^\s*ssl-default-server-curves X25519MLKEM768$'
  for directive in ssl-default-bind-sigalgs ssl-default-bind-client-sigalgs ssl-default-server-sigalgs ssl-default-server-client-sigalgs; do
    require_line "${file}" "^\s*${directive} mldsa65:mldsa87$"
  done
  forbid_line "${file}" 'rsa_|ecdsa_|ed25519|ed448|secp256r1|secp384r1|X25519:|:X25519|prime256v1'
  forbid_line "${file}" 'verify (none|optional)'
  forbid_line "${file}" 'crt-ignore-err|ca-ignore-err'
  # Every outbound TLS hop verifies the peer against the PKI chain.
  require_line "${file}" '^\s*server backend backend:8080 ssl crt /etc/quantum-bank/tls/gateway-client\.pem ca-file /etc/quantum-bank/tls/ca-chain\.crt verify required sni str\(backend\)'
  require_line "${file}" '^\s*server keycloak keycloak:8443 ssl ca-file /etc/quantum-bank/tls/ca-chain\.crt verify required sni str\(keycloak\)'
  # Loopback-only egress binds.
  require_line "${file}" '^\s*bind 127\.0\.0\.1:18081$'
  require_line "${file}" '^\s*bind 127\.0\.0\.1:18082$'
done

require_line "${repo_dir}/tls/haproxy-bootstrap.cfg" '^\s*bind :8080 ssl crt /etc/quantum-bank/tls/gateway-server\.pem alpn http/1\.1$'
require_line "${repo_dir}/tls/haproxy-bootstrap.cfg" '^\s*server krakend 127\.0\.0\.1:18080$'
require_line "${repo_dir}/tls/haproxy-banking.cfg" '^\s*bind :8443 ssl crt /etc/quantum-bank/tls/gateway-server\.pem ca-file /etc/quantum-bank/tls/ca-chain\.crt verify required alpn http/1\.1$'
require_line "${repo_dir}/tls/haproxy-banking.cfg" '^\s*server krakend 127\.0\.0\.1:18443$'

echo "pqc-gateway-ok"
