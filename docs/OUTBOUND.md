# Outbound webhook service

HookLab can publish application events to configured subscriber endpoints. The
first release is deliberately configuration-first: applications, endpoints,
and subscriptions are reviewed in a versioned file, while token and signing
secret values come only from environment variables.

The API, SQLite commit, retry queue, signing step, dead-letter handling, and
manual replay form one runnable loop. Delivery remains **at least once**;
consumers must deduplicate the stable delivery or event identifier.

## Configure resources

See [`examples/gateway/outbound-config.json`](../examples/gateway/outbound-config.json).
The `outbound` object contains:

- `applications`: publisher namespaces with an `id` and
  `publish_token_env`;
- `endpoints`: trusted HTTP(S) destinations with a unique `id`, URL,
  `signing_secret_env`, and public `key_id`;
- `subscriptions`: an application-to-endpoint relationship with one or more
  exact event types or `*`.

Exact event types and public key IDs may contain letters, digits, `.`, `_`,
`-`, `:`, or `/` and are limited to 128 characters. `*` is reserved for a
complete subscription wildcard and is not a publishable event type.

Inline `token`, `publish_token`, `secret`, or `signing_secret` values are
rejected. IDs are unique, references must resolve, and every subscription
creates independent work. Consequently, overlapping exact and wildcard
subscriptions intentionally produce two deliveries.

Endpoint URLs must use `http://` or `https://`, include a non-empty host, and
may include a numeric port from 1 through 65535. Bracketed IPv6 hosts are
supported. Credentials/userinfo (`@`), query strings, fragments, backslashes,
and ASCII whitespace or control characters are rejected. Do not put tokens,
API keys, or other sensitive data in an endpoint URL; configure signing
secrets through `signing_secret_env` instead.

Set the values and start the checked configuration:

```bash
export HOOKLAB_SECRET=ingress-development-secret
export HOOKLAB_PUBLISH_ORDERS=publisher-development-token
export HOOKLAB_SIGN_WAREHOUSE=endpoint-development-secret
moon run --target js cmd/hooklab -- config-check examples/gateway/outbound-config.json
moon run --target js cmd/hooklab -- serve-config examples/gateway/outbound-config.json
```

PowerShell:

```powershell
$env:HOOKLAB_SECRET = "ingress-development-secret"
$env:HOOKLAB_PUBLISH_ORDERS = "publisher-development-token"
$env:HOOKLAB_SIGN_WAREHOUSE = "endpoint-development-secret"
moon run --target js cmd/hooklab -- serve-config examples/gateway/outbound-config.json
```

## Publish an event

```bash
curl -i \
  -X POST http://127.0.0.1:8787/api/outbound/applications/orders/events/order.created \
  -H 'Authorization: Bearer publisher-development-token' \
  -H 'Idempotency-Key: order-42-created' \
  -H 'Content-Type: application/json' \
  --data '{"order_id":"order-42","amount":4200}'
```

The exact request body is retained and signed for each delivery attempt. The
body must use the exact `application/json` media type (parameters such as
`charset=utf-8` are allowed), contain valid JSON, and be at most one MiB. The
idempotency key is mandatory.
Reusing a key with the same application, event type, and exact payload returns
the original event as a duplicate without new work. Reusing it with different
content returns `409 idempotency_conflict`.

| Status | Meaning |
|---:|---|
| 202 | New event and all matching delivery jobs committed atomically |
| 200 | Exact duplicate; no new delivery jobs |
| 400 | Missing idempotency key |
| 401 | Missing or invalid publisher token |
| 404 | Unknown application |
| 409 | Idempotency key reused with different content |
| 415 | Body is not declared as JSON |
| 422 | Invalid JSON or invalid publication plan |

`GET /api/outbound/catalog` returns safe application, endpoint, and
subscription metadata. It never returns environment-variable names, tokens,
or signing secrets.

## Verify a delivered webhook

Every outbound attempt contains:

```text
X-HookLab-Event-Id
X-HookLab-Delivery-Id
X-HookLab-Event-Type
X-HookLab-Timestamp
X-HookLab-Key-Id
X-HookLab-Signature: v1=<lowercase hex HMAC-SHA256>
```

The signed bytes are:

```text
v1\n{timestamp}\n{deliveryId}\n{eventId}\n{eventType}\n{exactRawBody}
```

A consumer should:

1. read the exact body bytes before JSON parsing;
2. reject timestamps outside its chosen freshness window, for example 300
   seconds;
3. choose the secret identified by `X-HookLab-Key-Id`;
4. compute HMAC-SHA256 over the canonical string and compare it in constant
   time;
5. deduplicate with `X-HookLab-Delivery-Id` before applying side effects.

The timestamp and signature can change on retry. Event and delivery IDs and
the payload remain stable. Redirects are not followed automatically, which
prevents a configured endpoint from forwarding signed traffic to another
location.

## Current boundary

- Resources are configuration-managed; dynamic CRUD and a consumer portal are
  future work.
- Endpoint URLs are trusted operator configuration. Tenant-controlled URLs
  require SSRF protections before they are enabled.
- One endpoint currently has one active signing secret and key ID. The core
  verification helper already accepts multiple secrets for rotation, while
  runtime overlap and portal-driven rotation remain roadmap work.
- Treat an endpoint ID, URL, and key ID as one immutable configuration version
  while its deliveries are queued. For rotation, add a new endpoint ID/key
  ID/secret environment variable, move subscriptions to it, and keep the old
  endpoint configured until its deliveries are terminal. The Worker refuses
  to sign a persisted delivery if its stored URL or key ID no longer matches
  the configured endpoint, instead of sending a misleading signature.
- SQLite provides transactional single-host persistence and safe competing
  claims. PostgreSQL and cross-host coordination remain roadmap work.
