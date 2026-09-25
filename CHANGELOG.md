# Changelog

All notable changes are documented here. HookLab follows semantic versioning.

## Unreleased

### Added

- PostgreSQL delivery-attempt records are now created with the claim, marked
  interrupted on expired-lease takeover, and finalized transactionally; SLO
  latency excludes attempts with unknown completion time.
- Contract-version compatibility decisions now run in the MoonBit domain core
  rather than the Node.js PostgreSQL adapter, with cross-target and gateway tests.
- The gateway rate-limit E2E now measures monotonic network arrival time and
  allows CI transport jitter; exact window boundaries remain unit-tested.
- A reproducible PostgreSQL order-event showcase that kills a Worker mid-delivery,
  checks lease takeover and exact delivery identity, and reports bounded
  synthetic loopback timings without claiming production performance.
- A quarterly evaluation evidence guide clarifying the MoonBit/Node.js boundary,
  demonstration steps, current limitations, and the absence of external adoption evidence.
- A separate PostgreSQL application-event runtime with tenant-scoped
  applications, endpoints and subscriptions, RBAC management tokens, audit
  records, a consumer portal, and one-time credential rotation.
- Transactional event/fan-out persistence, multi-instance `SKIP LOCKED`
  claims, renewable fenced leases, signed delivery, retry history and manual
  dead-letter recovery.
- Versioned event contracts with a deliberately bounded JSON Schema subset,
  compatibility checks and CloudEvents 1.0 structured JSON publication.
- Prometheus metrics, a tenant-scoped 24-hour SLO, dead-letter/backlog alerts,
  alert-rule example, and PostgreSQL integration tests in CI.
- `docs/PLATFORM.md` with deployment, API, security, operation and test notes.
- Version 1 declarative gateway configuration with named content routes.
- `config-check` full-issue validation and `serve-config` runtime startup.
- Environment-variable-only secret references; inline secrets are rejected.
- Cross-platform configuration tests and a runnable configuration E2E test.
- Per-route deterministic JSON set, remove, and copy transformations.
- Explicit UTF-8 input, output, and operation-count budgets with atomic rejection.
- Persisted route-specific outputs that remain stable during manual replay.
- Process-local per-target outbound concurrency and rolling-window rate limits,
  including retries and manual replays, with a global 16-attempt ceiling.
- End-to-end coverage for target isolation and limit enforcement.
- Opt-in per-target circuit breakers with half-open probes and permanent-4xx
  neutrality; process-local latency histograms with opaque target labels.
- End-to-end coverage for circuit opening, replay admission, recovery, and
  metric redaction.
- A pure MoonBit outbound publication domain with deterministic identifiers,
  content fingerprints, exact/wildcard subscriptions, publisher token checks,
  and provider-neutral HMAC-SHA256 signatures.
- Configuration-managed outbound applications, endpoints, and subscriptions,
  plus an authenticated and idempotent publication API.
- A Node.js 24 SQLite WAL adapter that atomically commits idempotency, accepted
  events, and all delivery jobs, including version 1 `state.json` migration.
- Fenced Worker leases with conditional in-flight renewal, expiry, crash
  recovery, and stale-completion rejection in both the MoonBit domain and
  runnable gateway.
- End-to-end coverage for signed retry, content-conflict idempotency, catalog
  and management redaction, legacy migration, and Worker crash takeover.

### Changed

- The runnable gateway now requires Node.js 24+ and stores runtime state in
  `hooklab.sqlite`; non-gateway JS CLI commands remain compatible with Node.js
  18+.

### Maintenance

- Keep strict CI checks on current MoonBit toolchains while temporarily disabling
  two legacy-API migration warnings; other warnings remain fatal.

## 0.2.0 — September 2026 maintenance cycle

Baseline: 548c5e2 (0.1.0 functionality completed before this maintenance cycle).

### Added

- A MoonBit event store and stable accepted-event model.
- A deterministic delivery queue with pending, scheduled, in-flight, delivered,
  dead-lettered, and cancelled states.
- Per-ordering-key claim serialization.
- Manual recovery of dead-lettered deliveries.
- A Webhook contract validator that reports all header, payload-path, provider,
  event-type, JSON, and size issues in one pass.
- A MoonBit gateway orchestration layer that verifies before persistence,
  performs scoped idempotency checks, redacts diagnostics, evaluates routes,
  and enqueues delivery work.
- A runnable Node.js gateway adapter with loopback-only binding, one-megabyte
  ingress limit, atomic local state snapshots, restart recovery, reliable
  delivery, Retry-After, dead-letter handling, replay APIs, and a local
  dashboard.
- An end-to-end test covering authentication, deduplication, persistence,
  redaction, retry, and eventual delivery.

### Security

- Public event APIs never expose retained raw request bodies.
- Signature and common authentication headers are redacted before persistence
  as diagnostic metadata.
- The management server binds to 127.0.0.1.
- Only statically configured HTTP(S) delivery targets are used.

## 0.1.0 — August 2026

- GitHub, Stripe, Feishu/Lark, and generic HMAC verification.
- Pure MoonBit SHA-256 and HMAC-SHA256.
- Freshness, secret rotation, replay protection, scoped idempotency, JSON
  routing, redaction, retry decisions, fixtures, reports, and CLI tools.
