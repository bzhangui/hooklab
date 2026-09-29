# Changelog

All notable changes are documented here. HookLab follows semantic versioning.

## Unreleased

### Added

- A one-command reviewer smoke path, including independent published-package
  event ID, outbound signing and tamper rejection; an optional disposable
  PostgreSQL path covers the multi-persona event-delivery flow.
- An 85% line coverage gate for selected deterministic Node.js platform
  helpers, separate from MoonBit core coverage and PostgreSQL E2E tests.
- A reviewed MoonBit toolchain version-drift gate in CI and the container
  build; upstream binary checksums are not yet pinned.
- A no-secret local diagnostics command and first-event CLI, with a fourth
  portal onboarding step and a complete first-event runbook.
- An optional exact-host outbound allowlist, checked both when creating
  endpoints and on every delivery attempt.
- A manually triggered 10/30-round synthetic repeatability workflow and
  explicit capacity-evidence protocol.

### Security and maintenance

- Pinned CI action references to reviewed commit SHAs and configured weekly
  dependency-update pull requests.
- Enabled GitHub private vulnerability reporting and documented its route.

### Limits

- These changes do not establish a real external-user pilot, production
  throughput/SLO, cross-host recovery, database row-level security or a
  stable 1.0 API. The local PostgreSQL platform remains a controlled trial.

## 0.3.0-rc.5 — 2026-09-28

### Added

- A browser-only, six-scenario teaching showcase with no live API calls or
  credentials; synthetic results are clearly distinguished from user evidence.
- A three-step, non-submitting onboarding guide in the local tenant portal;
  resource counts show progress and example buttons only prefill form fields.
- A bounded multi-persona acceptance runner covering gateway, receiver, tenant,
  quota, retry, failover and security paths. The local full profile creates its
  own loopback PostgreSQL container; CI runs three independent database rounds
  and uploads only a secret-free summary.
- An optional per-process HTTP in-flight admission fuse with retryable 503s
  and Prometheus counters, plus a TLS/rate-limiting reverse-proxy example.
- Product-mode, compatibility and production-boundary documentation.

### Limits

- No authorized external user pilot, production soak, off-host disaster
  recovery, database row-level security or zero-downtime active-queue migration.
  The static showcase and synthetic tests must not be presented as substitutes.

## 0.3.0-rc.4 — 2026-09-28

### Documentation

- Corrected the Mooncakes package README snapshot after the `0.3.0-rc.3`
  archive shipped with an obsolete pre-publication statement. Package usage
  now points to a fresh-consumer check of the latest registry version.
- Added a one-page reviewer path for independent package installation, CLI
  demonstration, local platform startup and CI evidence.

### Quality

- Added an RFC 4231 HMAC long-key vector and reverse length-mismatch test;
  the selected MoonBit domain packages now have repeatable coverage floors.
- CI now checks a fresh Mooncakes consumer, a Windows PowerShell demo and
  lockfile license metadata in addition to the existing Linux and PostgreSQL
  paths.

## 0.3.0-rc.3 — 2026-09-28

### Added

- Published `bzhangui/hooklab@0.3.0-rc.3` to Mooncakes on 2026-09-28;
  independently verified the public registry metadata and a fresh consumer
  project importing and calling `hooklab/crypto`. CI enforces the compiler
  minimum and package checks exclude private application materials,
  credentials and backups. The published archive retains its pre-release
  README snapshot; the next version should include this corrected notice.
- PostgreSQL v3 provider-ingress credentials and MoonBit signature verification
  now route authenticated third-party callbacks through the same tenant event,
  subscription, signing and worker pipeline; invalid requests have no writes.
- Optional shared tenant hourly body-byte and pending-delivery caps, plus a
  redacted event timeline and acceptance-to-final-delivery latency metric/SLO.
- A local SQLite-backed receiver example keeps deduplication and a sample
  business update in one transaction, with restart and conflict tests.
- A private, checksummed SQLite terminal-history transfer supports preview and
  confirmed PostgreSQL event import; active queue work and secrets are excluded.
- An experimental machine-readable OpenAPI description for core platform routes.
- Node.js receiver verifier with a MoonBit cross-language signature vector,
  tamper/stale/ambiguous-header tests, a loopback example and containerized
  delivery conformance checks. The example does not claim durable deduplication.
- PostgreSQL v1/v2-to-v3 additive migrations, gated for existing
  databases by an explicit post-backup upgrade flag; read-only schema inspection.
- Preview-first, tenant-scoped, bounded retention batches for old terminal
  events and attempts. No live data was purged by this change.
- Synthetic showcase now verifies signatures at the receiver and asserts one
  unique accepted consumer ID across failover attempts.

### Remaining limits

- No authorized external pilot, long-duration production load test, published
  npm SDK, live SQLite queue migration, general export/import or off-host
  backup automation. At the time of `0.3.0-rc.3`, the latest tagged release
  remained `0.3.0-rc.2`.

## 0.3.0-rc.2 — 2026-09-25

Controlled-trial update; no claim of a real user pilot or production readiness.

### Added

- CI-only receiver validates a full containerized delivery: contract rejection,
  HMAC signatures, 503-to-204 retry, stable delivery identity, attempt history,
  and duplicate suppression.
- Isolated backup restore now checks all expected tables and decrypts a restored
  endpoint secret when present; a private manifest and offline checksum/key
  inspection command support operator-managed off-host copies. CI also boots a
  second app against a fresh-volume restore of the synthetic backup.
- MoonBit platform callback tests and an explicit MoonBit/Node.js evidence map;
  a controlled-pilot authorization card and recovery runbook document what is
  and is not externally verified.
- An optional PostgreSQL-serialized hourly accepted-event cap per tenant,
  tested with concurrent publication through two instances; it does not
  replace general request/byte rate limiting.

## 0.3.0-rc.1 — 2026-09-25

Release candidate for local trial and evaluation, not a production-readiness claim.

### Added

- A loopback-only Docker Compose trial deployment with generated private
  credentials, a non-root application container, and a backup/isolated-restore
  verification command. Real-user evidence still requires an authorized pilot.
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
