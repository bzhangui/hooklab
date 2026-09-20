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
- [ ] Circuit breaking and delivery latency histograms
- [ ] Export/import and retention controls

## 0.4 — Transactional adapters

- Storage interface with SQLite and PostgreSQL implementations
- Transactional idempotency and work claiming
- Lease expiry and worker crash recovery
- Migration tooling and backup verification

## 0.5 — Outbound webhook service

- Applications, consumers, endpoints, and subscriptions
- Event publication API and provider-neutral signing
- Consumer portal for delivery history and secret rotation
- SDKs and conformance fixtures

## 1.0 — Production hardening

- Authenticated multi-tenant control plane
- Role-based access and audit trail
- High-availability deployment guide
- Compatibility and performance baselines
- Stable API and upgrade policy
