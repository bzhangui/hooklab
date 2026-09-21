# Security policy and threat model

## Threats addressed

HookLab is designed to reduce forged webhooks, stale-event replay, duplicate side effects, sensitive diagnostic leakage, unbounded delivery retry, and unsafe HTML report rendering.

The implementation validates signature syntax and compares fixed-length digests without early exit. Timestamp checks reject stale and implausibly future events. Idempotency is evaluated only after authentication. Default redaction traverses nested JSON and covers common credential and personal-data keys. Offline HTML escapes all untrusted content and contains no script or remote asset.

## Boundaries and residual risks

- The core in-memory stores are process-local. The Node gateway uses SQLite WAL transactions, unique constraints, leases, and fencing for same-host competing Workers. Cross-host deployments still require a shared PostgreSQL-style adapter.
- The gateway SQLite database and WAL may contain authenticated raw bodies and route-specific transformed bodies because exact delivery and replay require them. Protect the full data directory as production-sensitive material; public APIs expose neither body and show only redacted event copies.
- The built-in management server has no user authentication and therefore
  binds only to `127.0.0.1`. It rejects non-loopback `Host` values to block DNS
  rebinding and rejects cross-origin browser management writes. Remote
  deployments require an authenticated TLS reverse proxy, access control for
  `/api/*`, and an upstream `Host` rewritten to the loopback listener.
- Constant-time comparison reduces timing leakage in digest comparison, but a managed runtime and surrounding application can still introduce side channels. Do not expose detailed timing measurements.
- CLI secrets can be visible in shell history and process listings. Use `HOOKLAB_SECRET`/`HOOKLAB_PREVIOUS_SECRETS`, library integration, or a secret manager instead.
- Version 1 gateway configuration accepts only environment-variable names for secrets and rejects inline `secret`/`secrets` fields. Keep local environment files out of version control.
- Outbound configuration also rejects inline publisher tokens and signing secrets. Enabled resources fail startup when their configured environment variable is empty. The safe catalog API omits environment-variable names and all secret values.
- Route transforms are fixed set/remove/copy operations with mandatory byte and operation budgets. They run only after verification and complete before idempotency or persistence; failures return no partial output or side effects.
- Delivery targets are trusted startup configuration. Outbound delivery does not follow redirects. If targets become tenant-controlled, add an HTTP(S) allowlist, DNS rebinding protection, private-network and cloud-metadata policy before enabling them.
- The server limits request bodies to one MiB. Outbound attempts have per-target concurrency and optional rate policies plus a global 16-attempt ceiling, but counters are process-local and reset on restart. Ingress rate limiting, tenant quotas, TLS termination, and multi-instance coordination remain deployment responsibilities.
- Circuit breakers and latency metrics are process-local. The metrics endpoint
  exposes only fixed-bucket counts and anonymous target labels; it does not
  expose destination URLs, payloads, or headers. Management API access still
  requires the loopback/proxy boundary above.
- Delivery is at least once. Downstream consumers must deduplicate with the HookLab delivery or event identifier.
- Publisher idempotency prevents repeated HookLab work for the same application/key/content, but it does not make downstream side effects exactly once. Reusing a key with different content is rejected.
- Redaction is key-based and cannot recognize every sensitive value. Configure additional field names for domain-specific data.

## Reporting a vulnerability

Do not publish exploitable details in a public issue. Contact the repository maintainer privately with the affected version, reproduction steps, impact, and a proposed mitigation if available. Avoid including real secrets or customer payloads.
