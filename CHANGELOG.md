# Changelog

All notable changes are documented here. HookLab follows semantic versioning.

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
