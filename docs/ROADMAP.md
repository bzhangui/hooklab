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
- [ ] Export/import and retention controls

## 0.4 — Transactional adapters

- [x] SQLite WAL adapter with atomic event and delivery commits
- [ ] PostgreSQL adapter and shared storage contract suite
- [x] Transactional idempotency and conditional work claiming
- [x] Lease expiry, fencing, and worker crash recovery
- [ ] General migration tooling and backup verification

## 0.5 — Outbound webhook service

- [x] Configuration-managed applications, endpoints, and subscriptions
- [x] Authenticated event publication API and provider-neutral signing
- [ ] Dynamic consumer management and authenticated control plane
- [ ] Consumer portal for delivery history and secret rotation
- [ ] SDKs and conformance fixtures

## 1.0 — Production hardening

- Authenticated multi-tenant control plane
- Role-based access and audit trail
- High-availability deployment guide
- Compatibility and performance baselines
- Stable API and upgrade policy
