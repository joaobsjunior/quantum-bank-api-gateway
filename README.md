# Quantum Bank API Gateway

KrakenD API Gateway configuration for Quantum Bank.

Initial responsibilities:

- Route all mobile app traffic to backend services
- Enforce gateway-level authentication and transport security policies
- Integrate with mTLS certificate flow
- Provide Dockerized local gateway runtime

## Phase 1 Contract Ownership

The API Gateway owns and consumes these Phase 1 contracts:

- [Gateway Boundary Contract](docs/contracts/gateway-boundary.md) for CONT-02 public route ownership, JWT validation handoff, mTLS boundaries, backend routing, problem details, and forbidden bypasses.
- [Quantum Bank OpenAPI v1](openapi/quantum-bank-v1.yaml) for the CONT-02 app-facing route and schema source of truth.

Later KrakenD implementation must keep mobile traffic on public gateway paths and must not own certificate issuance, renewal, or revocation.

## Phase 2 OAuth2 Gateway Policy

Phase 2 adds the local JWT authorization policy for the app-facing gateway.

- [OAuth2 Gateway Policy Contract](docs/contracts/oauth2-gateway-policy.md) documents AUTH-02 issuer, audience, scope, negative-token, and problem-details expectations.
- [krakend.json](krakend.json) contains the source-level KrakenD JWT validator policy for the Phase 1 route surface.

## Phase 3 mTLS Gateway Split

Phase 3 uses two KrakenD configs because bootstrap must work before the mobile
app has a client certificate, while protected banking traffic must require one.

- [krakend-bootstrap.json](krakend-bootstrap.json) exposes `/auth/otk` and
  `/auth/csr` on `8080` with OAuth2Bearer and gateway-to-backend `client_tls`.
- [krakend-banking.json](krakend-banking.json) exposes `/pix/transfers`,
  `/statements`, and `/profile` on `8443` with OAuth2Bearer plus mTLS.
- [krakend.json](krakend.json) remains a bootstrap-compatible compatibility
  entrypoint and documents the split.
- Missing or untrusted app certificates on banking routes fail during TLS
  handshake before HTTP problem details are available.

## Post-Quantum TLS Terminators

KrakenD is built on Go `crypto/tls`, which cannot terminate ML-DSA certificates
nor verify ML-DSA-signed peers. The gateway layer therefore owns two artifacts:

- [krakend-bootstrap.json](krakend-bootstrap.json) / [krakend-banking.json](krakend-banking.json):
  KrakenD binds **`127.0.0.1` only** (`18080` / `18443`), carries no `tls` or
  `client_tls` block, reaches the backend through `http://127.0.0.1:18081` and
  the issuer JWKS through `http://127.0.0.1:18082`.
- [tls/haproxy-bootstrap.cfg](tls/haproxy-bootstrap.cfg) / [tls/haproxy-banking.cfg](tls/haproxy-banking.cfg),
  packaged by [Dockerfile.tls](Dockerfile.tls) (`haproxy:3.2-alpine`, OpenSSL
  3.5): HAProxy shares the KrakenD network namespace, publishes `8080`/`8443`
  with the PKI-issued ML-DSA-65 server certificate, negotiates only TLS 1.3 with
  `X25519MLKEM768` and `mldsa65:mldsa87`, requires an ML-DSA client certificate
  on the banking listener (failing inside the handshake otherwise), and
  provides the loopback egress that presents the `gateway-client` ML-DSA
  identity to the backend and verifies the issuer.

Loopback traffic never leaves the network namespace; every socket that crosses
a container or host boundary is post-quantum authenticated and encrypted.
`scripts/verify-pqc-gateway.sh` enforces the policy statically and
`scripts/ci-validate.sh` also runs `haproxy -c` against freshly generated
ML-DSA material.

## Phase 6 Docker Runtime

The gateway has a [Dockerfile](Dockerfile) based on the official KrakenD image
with the bootstrap and banking configs copied into `/etc/krakend`. Compose runs
two gateway services from the same image: bootstrap on `8080` and banking on
`8443`. Both services mount PKI-owned runtime TLS material, and the banking
listener requires app-to-gateway mTLS.

JWKS retrieval leaves KrakenD as plain HTTP to the loopback egress
`127.0.0.1:18082`, where HAProxy authenticates the issuer with its ML-DSA
certificate; `disable_jwk_security` is allowed only for that loopback URL and
checked by `scripts/verify-pqc-gateway.sh`.

## Testing & CI

- Validate gateway config locally: `./scripts/ci-validate.sh` runs `krakend
  check` on every config (via local binary or the `krakend:2.13.4` Docker
  image), `haproxy -c` on both terminator configs with generated ML-DSA
  material, `scripts/verify-bootstrap-scopes.sh` and
  `scripts/verify-pqc-gateway.sh`.
- CI (`.github/workflows/ci.yml`) runs the same validation gate on every push/PR
  to `main`.

## Runtime Requirements

KrakenD is the lightest part of the stack (a small Go binary).

### Recommended configuration

**Per gateway listener:**

| Resource | Recommended |
| --- | --- |
| Memory | **256 MB** |
| CPU | **0.5 vCPU** |
| Disk | **~70 MB** KrakenD image + **~25 MB** HAProxy terminator image (shared by both listeners) |

Docker equivalent per listener: `--memory=256m --cpus=0.5`.

Compose starts **two** listeners from the same image — `gateway-bootstrap`
(8080) and `gateway-banking` (8443) — so budget **~512 MB RAM and ~1 vCPU total**
for both.

### Good to know

- The image is pulled only once and shared by both listeners.
- Stateless: no data volume, only read-only config and PKI TLS/trust mounts.
