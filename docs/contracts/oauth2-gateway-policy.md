# OAuth2 Gateway Policy Contract

Requirement: AUTH-02

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

Accepted requests route to `http://backend:8080` inside the container network.
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

## Phase 3 mTLS Handoff

Phase 2 enforces OAuth2 JWT validation and scope authorization only.

Phase 3 owns app-to-gateway mTLS and gateway-to-backend mTLS enforcement. The
`krakend.json` `_phase3_mtls_placeholder` field preserves that handoff in the
runtime contract.

## Out Of Scope

Phase 2 does not implement:

- App-to-gateway mTLS.
- Gateway-to-backend mTLS.
- Certificate issuance, renewal, or revocation.
- Production identity provider hardening.
- Profile editing with `profile:write`.
