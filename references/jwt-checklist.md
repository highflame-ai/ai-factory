# JWT / Auth Checklist

Most platforms end up with several distinct token types, and confusing them is the most common security bug. **First step for any org adopting this checklist: enumerate your token types** in the table below, then apply the archetype checklists that match each one.

## Enumerate your token types

Fill in one row per credential that crosses a service boundary. The four archetypes below cover almost every platform:

| Token (yours)             | Archetype                | Issuer                                     | Verified by                        | Header                                      |
| ------------------------- | ------------------------ | ------------------------------------------ | ---------------------------------- | -------------------------------------------- |
| `<idp-session-token>`     | User session JWT (IdP)   | Your identity provider (e.g. Clerk, Auth0) | Server-side proxy via IdP JWKS, often exchanged for a platform-signed JWT | `Authorization: Bearer <token>`              |
| `<platform-jwt>`          | Platform-signed JWT      | Your auth service (e.g. signs RS256 with a private key) | Every downstream service (public key) | `Authorization: Bearer <token>`              |
| `<api-key>`               | API key                  | Your key-management service (prefixed opaque strings, e.g. `sk_...`) | Edge / gateway services            | `Authorization: Bearer <key>`                |
| `<internal-secret>`       | Internal service secret  | Env / k8s Secret                           | All services (constant-time compare) | `X-<Org>-Internal-Secret: <secret>` or similar |

Typical flows to document alongside the table:

- **Browser path:** IdP session → server-side proxy → token-exchange endpoint (IdP token → platform JWT) → backend services.
- **SDK path:** API key → gateway (validates against the key registry).
- **Service-to-service:** either the user's platform JWT (preserves tenant context) OR the internal secret (privileged backplane only).

## Archetype: user session JWT (identity provider)

- [ ] Verified server-side against the IdP's JWKS; keys refreshed, not pinned to a stale snapshot
- [ ] Never forwarded past the exchange boundary — downstream services see your platform JWT, not the IdP token
- [ ] Never exposed to browser-side bundles when the exchange happens in server code

## Archetype: platform-signed JWT

### Issuance checklist

- [ ] Asymmetric signing (e.g. RS256) from a private key that only the issuing service holds
- [ ] Claims include the tenant keys from `tenancy.keys` in `.aif/config.yml` (e.g. `account_id`, `project_id`), plus `user_id`, `exp`, `iat`, and an `iss` naming the issuing service
- [ ] `exp` is short (15 min is a good default); refresh via re-exchange, not long-lived JWTs
- [ ] No secrets in claims (no API keys, no internal-secret values)

### Verification checklist

- [ ] Public key loaded at boot; failure to load = service won't start
- [ ] `iss` validated against the expected value
- [ ] `exp` validated; clock skew tolerance ≤ 60s
- [ ] Tenant keys extracted from claims, never from headers/body (see `multi-tenancy-checklist.md`)
- [ ] Algorithm pinned (e.g. `["RS256"]`); reject `alg: none` and symmetric-alg-with-public-key confusion (e.g. `HS256` signed with the public key)
- [ ] On verification failure: 401, no claim leakage in the error body

## Archetype: API key

- [ ] Opaque, prefixed strings (a recognizable prefix like `sk_` aids secret scanning)
- [ ] Validated against the key registry at the edge; downstream services receive derived identity, not the raw key
- [ ] Tenant scope derived from the key record, never from the request
- [ ] Revocable without a deploy; lookups cached with short TTLs only

## Archetype: internal service secret

- [ ] Compared with a constant-time comparison (`subtle.ConstantTimeCompare` in Go, `secrets.compare_digest` in Python)
- [ ] Source: env var or secret store, never hard-coded
- [ ] Used only on internal endpoints; anything gateway-facing requires a platform JWT or API key
- [ ] Rotated by re-deploy; no DB-cached value

## Red flags

- A handler reading a tenant ID from a client-supplied header (e.g. `x-account-id`). Forbidden — claims only.
- A token verifier that defaults `algorithms=any`. Pin the expected algorithm.
- A test that signs a token with a symmetric alg and the public key. Means the verifier is mis-configured (would accept attacker-forged tokens).
- A token logged at INFO. Tokens are sensitive — DEBUG only, redact in prod.
- A new internal endpoint with no check for either a platform JWT OR the internal secret. Open relay.

## Common bugs

- **Forgetting to verify `exp`** — caught only when an old token reappears
- **Trusting a tenant key from the request body** — multi-tenancy break
- **Using the same signing keypair across dev/stage/prod** — rotate per env; loss of a dev key shouldn't compromise prod
- **Caching tenant-key derivation in middleware globals** — request-scoped only

## When you find a violation

Auth bugs are P0. Fix in-PR; do not ship and patch later. After fix:

1. Add a regression test (`tests/` in the repo, or the org regression suite at `regression.repo` from `.aif/config.yml` if the bug is cross-service; skip that half if `regression:` isn't configured)
2. If the bug existed in deployed code: check your traces/audit log for exploit traffic (via MCP observability tools if `mcp.namespace` is configured)
3. File a security ticket capturing scope and timeline
