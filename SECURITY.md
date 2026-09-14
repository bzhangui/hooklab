# Security policy and threat model

## Threats addressed

HookLab is designed to reduce forged webhooks, stale-event replay, duplicate side effects, sensitive diagnostic leakage, unbounded delivery retry, and unsafe HTML report rendering.

The implementation validates signature syntax and compares fixed-length digests without early exit. Timestamp checks reject stale and implausibly future events. Idempotency is evaluated only after authentication. Default redaction traverses nested JSON and covers common credential and personal-data keys. Offline HTML escapes all untrusted content and contains no script or remote asset.

## Boundaries and residual risks

- The core in-memory stores are process-local. The gateway adapter adds atomic single-node snapshots and restart recovery, but distributed deployments still require transactional shared storage.
- The gateway state file contains authenticated raw bodies because exact delivery and replay require them. Protect the data directory as production-sensitive material; public APIs expose only redacted copies.
- The built-in management server has no user authentication and therefore binds only to `127.0.0.1`. Remote deployments require an authenticated TLS reverse proxy and access control for `/api/*`.
- Constant-time comparison reduces timing leakage in digest comparison, but a managed runtime and surrounding application can still introduce side channels. Do not expose detailed timing measurements.
- CLI secrets can be visible in shell history and process listings. Use `HOOKLAB_SECRET`/`HOOKLAB_PREVIOUS_SECRETS`, library integration, or a secret manager instead.
- Delivery targets are trusted startup configuration. If targets become tenant-controlled, add an HTTP(S) allowlist, DNS rebinding protection, private-network policy, and redirect restrictions before enabling them.
- The server limits request bodies to one MiB, but ingress rate limiting, tenant quotas, TLS termination, and multi-instance coordination are deployment responsibilities.
- Delivery is at least once. Downstream consumers must deduplicate with the HookLab delivery or event identifier.
- Redaction is key-based and cannot recognize every sensitive value. Configure additional field names for domain-specific data.

## Reporting a vulnerability

Do not publish exploitable details in a public issue. Contact the repository maintainer privately with the affected version, reproduction steps, impact, and a proposed mitigation if available. Avoid including real secrets or customer payloads.
