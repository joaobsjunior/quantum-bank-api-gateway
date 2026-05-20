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
