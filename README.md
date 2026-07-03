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

## Phase 6 Docker Runtime

The gateway has a [Dockerfile](Dockerfile) based on the official KrakenD image
with the bootstrap and banking configs copied into `/etc/krakend`. Compose runs
two gateway services from the same image: bootstrap on `8080` and banking on
`8443`. Both services mount PKI-owned runtime TLS material, and the banking
listener requires app-to-gateway mTLS.

The local Keycloak issuer uses HTTP inside the Compose network, so the KrakenD
JWT validators explicitly allow local insecure JWKS retrieval. Production
deployment configs must replace that with HTTPS issuer/JWKS endpoints.

## Testing & CI

- Validate gateway config locally: `./scripts/ci-validate.sh` runs `krakend
  check` on every config (via local binary or the `krakend/krakend:2.13` Docker
  image) plus `scripts/verify-bootstrap-scopes.sh`.
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
| Disk | **~70 MB** image (shared by both listeners) |

Docker equivalent per listener: `--memory=256m --cpus=0.5`.

Compose starts **two** listeners from the same image — `gateway-bootstrap`
(8080) and `gateway-banking` (8443) — so budget **~512 MB RAM and ~1 vCPU total**
for both.

### Good to know

- The image is pulled only once and shared by both listeners.
- Stateless: no data volume, only read-only config and PKI TLS/trust mounts.
