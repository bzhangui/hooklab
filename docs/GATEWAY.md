# HookLab Gateway

HookLab Gateway is the runnable, self-hosted form of the HookLab libraries. It
accepts authenticated webhooks on a loopback HTTP endpoint, persists accepted
events, expands routes into delivery work, retries transient failures, and
keeps terminal failures in a dead-letter state.

## Start a gateway

The server currently uses the JavaScript target and Node.js 18 or newer:

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
| GET | /api/events | Redacted event metadata |
| GET | /api/deliveries | Delivery state and last failure |
| POST | /api/deliveries/:id/retry | Reset a dead letter for delivery |
| POST | /api/events/:id/replay | Create fresh work for an accepted event |

The API deliberately omits raw bodies. Raw bodies are retained in the local
state file only because authorized delivery and replay must preserve the exact
payload. Protect the data directory as production-sensitive material.

## Delivery behavior

- 2xx completes a delivery.
- 408, 425, 429, and 5xx are retried.
- Other HTTP responses are permanent failures.
- Transport errors are retried.
- Exponential delay is bounded by the MoonBit retry policy.
- A valid delta-seconds Retry-After can extend, but never shorten, the local
  delay.
- Exhausted and permanent failures become dead letters.
- In-flight work is changed to scheduled work when a process restarts.
- State updates use a temporary file followed by an atomic rename.

These rules provide at-least-once delivery. Consumers must use
X-HookLab-Delivery-Id or X-HookLab-Event-Id for downstream idempotency.

## Deployment boundary

The built-in server binds only to 127.0.0.1. For remote access, put an
authenticated TLS reverse proxy in front of it and restrict the management
paths. The current adapter is intended for a developer workstation,
single-node service, CI, and reproducible contest demonstrations. Multi-tenant
authentication and a transactional database adapter remain separate production
deployment concerns.

## End-to-end verification

~~~bash
node scripts/gateway-e2e.mjs
node scripts/gateway-deadletter-e2e.mjs
node scripts/gateway-restart-e2e.mjs
~~~

The tests start temporary loopback services, rejects the first two delivery
attempts, confirms eventual success, checks duplicate suppression and API
redaction, verifies a durable state file, and removes its temporary data.
