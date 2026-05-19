# Gateway Boundary Contract

Requirement: CONT-02

Owner: Quantum Bank API Gateway

This contract defines the app-facing API boundary owned by KrakenD for Quantum
Bank local v1.

## Public API Surface

Mobile app calls only KrakenD public paths.

The gateway owns the app-facing route surface described in
`api-gateway/openapi/quantum-bank-v1.yaml`.

The Phase 1 route surface is:

- `POST /auth/otk`
- `POST /auth/csr`
- `POST /pix/transfers`
- `GET /statements`
- `GET /profile`

No mobile contract may introduce backend service URLs as app origins.

## JWT Validation

Phase 2 configures JWT validation.

Protected gateway operations must require the `OAuth2Bearer` security scheme
from the OpenAPI contract. The gateway must reject missing, malformed, expired,
or invalid bearer tokens before routing to backend services.

Backend services may still validate caller context, but the public app boundary
for JWT enforcement belongs to KrakenD.

## mTLS Boundaries

Phase 3 configures app-to-gateway and gateway-to-backend mTLS.

The gateway consumes mobile client certificates issued through the PKI flow and
uses configured trust anchors to enforce protected route access. Gateway-to-
backend mTLS is a separate boundary from app-to-gateway mTLS and must be
configured explicitly.

KrakenD must not issue certificates or own PKI lifecycle. Certificate issuance,
renewal, revocation, and trust anchor ownership belong to the PKI layer.

## Backend Routing

KrakenD routes accepted requests to backend services after gateway policy checks
pass.

Routing rules must preserve:

- Request correlation id.
- Authenticated subject context.
- OTK and CSR bootstrap payloads.
- Problem details response media type.
- No direct mobile-to-backend route exposure.

Gateway routes must not require mobile clients to know backend hostnames, ports,
paths, or deployment topology.

## Problem Details

Error responses use RFC 9457 problem details with
`application/problem+json`.

Gateway-originated errors must include stable `errorCode` and `correlationId`
fields when possible. Gateway responses must avoid stack traces, internal route
configuration, backend hostnames, certificate authority internals, or token
values.

Backend problem responses may pass through the gateway when their shape matches
the OpenAPI contract.

## Forbidden Bypasses

The following bypasses are forbidden:

- Mobile app calling backend service URLs directly.
- Mobile app using a non-KrakenD base URL for protected APIs.
- Gateway accepting protected APIs without OAuth2 bearer validation.
- Gateway accepting protected banking APIs without the planned mTLS boundary.
- Gateway issuing certificates.
- Gateway renewing or revoking certificates.
- Backend returning non-problem-details errors for app-facing failures.

## Later Phase Handoff

Phase 2 consumes this contract to implement OAuth2 and JWT validation in the
gateway and backend route chain.

Phase 3 consumes this contract to implement app-to-gateway and
gateway-to-backend mTLS using PKI-owned trust material.

Later implementation must keep the OpenAPI route source of truth in the
`api-gateway` repo and keep mobile clients gateway-only.
