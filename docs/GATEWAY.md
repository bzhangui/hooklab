# HookLab Gateway

HookLab Gateway is the runnable, self-hosted form of the HookLab libraries. It
accepts authenticated webhooks on a loopback HTTP endpoint, persists accepted
events, expands routes into delivery work, retries transient failures, and
keeps terminal failures in a dead-letter state.

## Start a gateway

The server uses the JavaScript target and the built-in `node:sqlite` adapter,
so running the gateway requires Node.js 24 or newer. Other JS CLI commands do
not use SQLite and remain compatible with Node.js 18+.

### Declarative configuration (recommended)

Validate the versioned configuration before starting. The file contains only
environment-variable names and never the secret values themselves:

~~~bash
export HOOKLAB_SECRET=local-development-secret
export HOOKLAB_PREVIOUS_SECRETS=previous-secret
moon run --target js cmd/hooklab -- config-check examples/gateway/config.json
moon run --target js cmd/hooklab -- serve-config examples/gateway/config.json
~~~

The example demonstrates content-based named routes and a bounded route
transformation. See
[CONFIGURATION.md](CONFIGURATION.md) for the version 1 schema, supported
operators, defaults, transforms, and PowerShell commands. Transformation
semantics are documented in [TRANSFORMS.md](TRANSFORMS.md).

### Positional command

For normal use, keep secrets out of command history:

~~~bash
export HOOKLAB_SECRET=local-development-secret
export HOOKLAB_PREVIOUS_SECRETS=previous-secret
moon run --target js cmd/hooklab -- serve generic - http://127.0.0.1:9090/target 8787 .hooklab-data
~~~

A literal secret argument remains available for isolated demonstrations:

~~~bash
moon run --target js cmd/hooklab -- serve \
  generic \
  local-development-secret \
  http://127.0.0.1:9090/target \
  8787 \
  .hooklab-data
~~~

Open http://127.0.0.1:8787/ for the local dashboard. Send webhooks to:

~~~text
POST /hooks/github
POST /hooks/stripe
POST /hooks/feishu
POST /hooks/generic-hmac
~~~

The configured provider is the only provider accepted by that gateway instance.
Multiple delivery targets can be supplied as a comma-separated list; each
accepted event is fanned out into independent delivery work. Multiple rotating
secrets may also be supplied as a comma-separated argument; every candidate is
checked before a result is returned.

## Management API

| Method | Path | Purpose |
|---|---|---|
| GET | /health | Health and current counters |
| GET | /api/stats | Event and delivery counts |
| GET | /api/metrics | Process-local delivery latency histogram with opaque target IDs |
| GET | /api/events | Redacted event metadata |
| GET | /api/deliveries | Delivery state and last failure |
| GET | /api/outbound/catalog | Safe configured application, endpoint, and subscription metadata |
| POST | /api/outbound/applications/:app/events/:type | Authenticated, idempotent application event publication |
| POST | /api/deliveries/:id/retry | Reset a dead letter for delivery |
| POST | /api/events/:id/replay | Create fresh work for an accepted event |

For local inspection, run `curl http://127.0.0.1:8787/api/metrics`; use
`/api/deliveries` to see each delivery and its `circuitState`.

The API deliberately omits raw and transformed bodies. Raw bodies and any
route-specific transformed outputs are retained in the local SQLite database
because authorized delivery and replay must preserve the exact payload.
Protect the database, WAL, SHM, and backup copies as production-sensitive
material.

## Transaction and worker model

The gateway stores `hooklab.sqlite` in the configured data directory and uses
WAL mode, foreign keys, a busy timeout, and full synchronous commits. Provider
idempotency, the accepted event, and all routed delivery rows commit in one
`BEGIN IMMEDIATE` transaction. Outbound publication similarly commits its
application-scoped idempotency key, content fingerprint, event, and all
subscription deliveries together.

Workers claim rows with a conditional version update and persist an owner,
random lease token, expiry, and incremented fencing version before sending any
HTTP request. The default lease is 30 seconds and can be changed from 1 to 300
seconds with `HOOKLAB_LEASE_MS`. A live Worker renews its lease while the HTTP
request is in progress; work left by a stopped or crashed Worker is no longer
renewed and returns to `scheduled` after expiry. A completion updates a row
only if its owner, lease token, and version still match and the lease remains
valid, so an old Worker cannot overwrite a newer attempt after recovery.

An existing version 1 `state.json` is imported transactionally when the new
database is empty. The source file is retained as a migration backup. An
unreadable or unsupported legacy file fails startup instead of silently
starting with empty state.

## Delivery behavior

- 2xx completes a delivery.
- 408, 425, 429, and 5xx are retried.
- Other HTTP responses are permanent failures.
- Transport errors are retried.
- Exponential delay is bounded by the MoonBit retry policy.
- A valid delta-seconds Retry-After can extend, but never shorten, the local
  delay.
- Exhausted and permanent failures become dead letters.
- In-flight work is reclaimed after its persisted lease expires, including
  work left behind by a crashed process.
- Slow live attempts renew their leases conditionally, preventing healthy
  Workers from being mistaken for crashed ones while a request is still open.
- Event acceptance and publication use SQLite transactions; delivery updates
  use conditional owner, token, and version fencing.
- A route-specific transformed body is reused for retries and manual replay.
- Outbound attempts are admitted per target: one concurrent attempt by default,
  or the configured concurrency and rolling one-second start rate. A process
  never runs more than 16 simultaneous outbound attempts. Retries and manual
  replays pass through the same gate; waiting work stays pending or scheduled.
- Configured circuit breakers pause repeatedly failing targets without
  consuming delivery attempts or rate tokens. A single half-open probe runs
  after cooldown; unrelated targets continue. Permanent HTTP 4xx is neutral.
  Delivery rows expose `circuitState` as disabled, closed, open, or half_open.
- Completed attempts feed five disjoint latency buckets: up to 100, 500, 1000,
  and 5000 ms, then above 5000 ms. `/api/metrics` uses anonymous process-local
  target IDs, not destination URLs, payloads, or credentials.
  Bucket keys are `le_100_ms`, `gt_100_le_500_ms`, `gt_500_le_1000_ms`,
  `gt_1000_le_5000_ms`, and `gt_5000_ms`.
- Limits, circuit states, and latency metrics are process-local and reset on
  restart. They are not a distributed quota across gateway instances.
- Transformation failure returns HTTP 422 before idempotency or persistence.

These rules provide at-least-once delivery. Consumers must use
X-HookLab-Delivery-Id or X-HookLab-Event-Id for downstream idempotency.

## Deployment boundary

The built-in server binds only to 127.0.0.1. For remote access, put an
authenticated TLS reverse proxy in front of it and restrict the management
paths. The server rejects non-loopback `Host` values and cross-origin browser
management writes; a reverse proxy must therefore rewrite its upstream `Host`
header to `127.0.0.1:<gateway-port>`. The SQLite adapter is intended for a
developer workstation, single-host service, CI, and reproducible contest
demonstrations. Multiple gateway
processes on the same host can safely compete for the same database, but rate
limits, circuit breakers, and metrics remain process-local. Cross-host high
availability, PostgreSQL, tenant-controlled endpoint SSRF protection, and an
authenticated multi-tenant control plane remain future work.

## End-to-end verification

~~~bash
node scripts/gateway-e2e.mjs
node scripts/gateway-config-e2e.mjs
node scripts/gateway-limits-e2e.mjs
node scripts/gateway-circuit-e2e.mjs
node scripts/gateway-deadletter-e2e.mjs
node scripts/gateway-restart-e2e.mjs
node scripts/gateway-outbound-e2e.mjs
node scripts/gateway-lease-e2e.mjs
~~~

The tests start temporary loopback services, validate configuration, assert the
exact transformed body delivered to a receiver, reject the first two delivery
attempts, confirm eventual success, check duplicate suppression and API
redaction, verify a durable state file, exercise target concurrency/rate
limits, circuit recovery, 4xx neutrality, anonymous latency metrics,
cross-target isolation, signed outbound publication, idempotency conflicts,
Worker crash recovery, live lease renewal, and legacy-state migration, then
remove their temporary data. MoonBit lease tests separately verify that
expired or stale completions cannot mutate newer work.
