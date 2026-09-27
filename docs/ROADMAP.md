# Roadmap

HookLab evolves in independently useful layers. A roadmap item is not an
implied capability of the current release.

## 0.2 — Single-node event delivery platform

- Authenticated provider ingress
- Accepted-event and delivery domain models
- Atomic local persistence and restart recovery
- Fan-out, bounded retries, Retry-After, dead letters, and replay
- Contract checks, management API, local dashboard, and end-to-end tests

## 0.3 — Configurable operations (in progress)

- [x] Versioned declarative gateway configuration
- [x] Rule-based transforms with explicit size and execution budgets
- [x] Per-target concurrency and rate limits
- [x] Circuit breaking and delivery latency histograms
- [x] Preview-first PostgreSQL tenant event retention batches
- [x] Controlled SQLite terminal-event history export and preview-first PostgreSQL import
- [ ] General export/import and SQLite retention controls

## 0.4 — Transactional adapters

- [x] SQLite WAL adapter with atomic event and delivery commits
- [x] PostgreSQL application-event adapter with dedicated schema and multi-worker CI test
- [x] Transactional idempotency and conditional work claiming
- [x] Lease expiry, fencing, and worker crash recovery
- [x] Compose trial deployment with isolated database backup/restore verification
- [x] CI-only signed receiver, retry/duplicate conformance, backup manifest and restored-key verification
- [x] Optional shared PostgreSQL hourly accepted-event cap with cross-instance test
- [x] PostgreSQL provider ingress verified by MoonBit with atomic event and subscription persistence
- [ ] General migration tooling, off-host backup automation and production recovery exercise

## 0.5 — Outbound webhook service

- [x] Configuration-managed applications, endpoints, and subscriptions
- [x] Authenticated event publication API and provider-neutral signing
- [x] Tenant-scoped consumer management and authenticated RBAC control plane
- [x] Consumer portal for delivery history and secret rotation
- [x] Node.js receiver verifier, loopback example and MoonBit signature conformance vector
- [x] Durable local Node.js consumer sample with transactional deduplication and restart test
- [ ] Other-language SDKs and published package

## 1.0 — Production hardening

- [x] Authenticated multi-tenant application-event control plane
- [x] Role-based access and audit trail
- [ ] Database-level row security and external identity integration
- [x] Optional cross-instance hourly accepted-body byte and pending-delivery caps
- [ ] General cross-instance request/connection rate limiting and complete resource quotas
- [x] Gated PostgreSQL v1/v2-to-v3 additive schema migration and tenant-scoped retention batches
- [ ] Live SQLite-to-PostgreSQL queue/configuration migration and general schema upgrade tooling
- [x] Redacted tenant event timeline and acceptance-to-final-delivery latency metrics
- High-availability deployment guide
- Compatibility and performance baselines
- Stable API and upgrade policy
