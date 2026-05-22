# OAuth2 Gateway Policy Contract

Requirement: AUTH-02, MTLS-01, MTLS-02

Owner: Quantum Bank API Gateway

This contract defines the Phase 2 OAuth2 JWT policy enforced by KrakenD before
routing app-facing requests to backend services.

## Issuer

KrakenD validates tokens from the local Keycloak realm `quantum-bank-local`.

Container-network issuer:

- `http://keycloak:8080/realms/quantum-bank-local`

Container-network JWKS:

- `http://keycloak:8080/realms/quantum-bank-local/protocol/openid-connect/certs`

Accepted audience:

- `quantum-bank-api`

Accepted signing algorithm:

- `RS256`

## Protected Paths

The gateway applies JWT validation to every Phase 1 app-facing route:

- `POST /auth/otk`
- `POST /auth/csr`
- `POST /pix/transfers`
- `GET /statements`
- `GET /profile`

Accepted requests route to `https://backend:8080` inside the container network.
Mobile clients must never use that backend origin directly.

## Scope Matrix

| Path | Method | Required scopes |
| --- | --- | --- |
| `/auth/otk` | `POST` | `openid`, `profile` |
| `/auth/csr` | `POST` | `openid`, `profile` |
| `/pix/transfers` | `POST` | `pix:write` |
| `/statements` | `GET` | `statements:read` |
| `/profile` | `GET` | `profile:read` |

The `scope` claim is space-delimited. Missing required scopes are rejected
before backend routing.

## Negative Token Matrix

| Case | Expected result |
| --- | --- |
| missing token | `401 application/problem+json` |
| malformed token | `401 application/problem+json` |
| expired token | `401 application/problem+json` |
| wrong issuer | `401 application/problem+json` |
| wrong audience | `401 application/problem+json` |
| missing scope | `403 application/problem+json` |

The gateway must not route any request that fails issuer, audience, token
validity, or endpoint scope checks.

## Problem Details

Gateway-originated authorization failures use RFC 9457 problem details with
`application/problem+json`.

Responses must include stable `status`, `title`, `errorCode`, and
`correlationId` fields when possible. Responses must not expose token values,
backend hostnames, stack traces, route internals, or PKI internals.

## Phase 3 mTLS Enforcement

Phase 3 keeps OAuth2 JWT validation and scope authorization active while adding
mTLS at two boundaries.

| Listener config | Port | App-to-gateway certificate policy | Routes |
| --- | --- | --- | --- |
| `krakend-bootstrap.json` | `8080` | OAuth2-only; no `enable_mtls` because the app does not have a client certificate yet. | `/auth/otk`, `/auth/csr` |
| `krakend-banking.json` | `8443` | OAuth2 plus mTLS; `tls.enable_mtls=true` and `tls.ca_certs` trusts the mobile issuing CA. | `/pix/transfers`, `/statements`, `/profile` |

Gateway-to-backend mTLS protects every configured hop, including bootstrap
routes. Both listener configs use HTTPS backend hosts and top-level
`client_tls.client_certs` for the gateway client certificate.

D-22: Protected banking routes `POST /pix/transfers`, `GET /statements`, and
`GET /profile` require app-to-gateway mTLS.

D-23: Bootstrap routes `POST /auth/otk` and `POST /auth/csr` remain OAuth2-only
at the app-to-gateway hop before the app has a client certificate.

D-24: Gateway-to-backend mTLS protects every configured gateway-to-backend hop,
including bootstrap routes.

D-28: OpenAPI and gateway docs reflect OAuth2-only bootstrap and OAuth2 plus
mTLS banking calls.

Missing, invalid, expired, wrong-environment, or untrusted certificates fail at
the TLS handshake layer. These failures are expected as handshake failure or TLS
alert results rather than `application/problem+json`, because the HTTP request
does not reach the route handler.

## Out Of Scope

Phase 3 does not implement:

- Certificate issuance, renewal, or revocation.
- Production identity provider hardening.
- Profile editing with `profile:write`.
