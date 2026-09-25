# Security policy and threat model

## Threats addressed

HookLab is designed to reduce forged webhooks, stale-event replay, duplicate side effects, sensitive diagnostic leakage, unbounded delivery retry, and unsafe HTML report rendering.

The implementation validates signature syntax and compares fixed-length digests without early exit. Timestamp checks reject stale and implausibly future events. Idempotency is evaluated only after authentication. Default redaction traverses nested JSON and covers common credential and personal-data keys. Offline HTML escapes all untrusted content and contains no script or remote asset.

## Boundaries and residual risks

- The core in-memory stores are process-local. `serve-config` uses SQLite WAL for same-host Workers. The separate `serve-platform` adapter uses shared PostgreSQL for multiple Workers; neither mode provides exactly-once delivery.
- The gateway SQLite database and WAL may contain authenticated raw bodies and route-specific transformed bodies because exact delivery and replay require them. Protect the full data directory as production-sensitive material; public APIs expose neither body and show only redacted event copies.
- The SQLite built-in management server has no user authentication and therefore
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

## PostgreSQL platform security boundary

- Tenant management APIs require hashed bearer tokens with Owner/Developer/Viewer roles, and every query is scoped by tenant ID. The database schema adds composite tenant/event foreign keys, but does not enable PostgreSQL row-level security; the application and database account remain trusted components. Use a dedicated least-privilege database account.
- Publisher tokens are generated randomly and stored only as SHA-256 digests. Endpoint signing keys and queued-delivery snapshots are encrypted with AES-256-GCM. Keep `HOOKLAB_ENCRYPTION_KEY` in a secret manager and back it up separately from PostgreSQL; loss of this key prevents signing previously queued work. Key material is returned only when created or rotated.
- Platform management APIs return metadata, not raw event bodies or stored encrypted secrets. PostgreSQL itself holds plaintext event bodies to support exact delivery. Treat backups, SQL access, logs, and snapshots as sensitive. Role tokens are not a substitute for network access controls.
- Tenant-configured targets allow HTTPS only, except an explicit loopback HTTP integration-test flag. Creation and every attempt resolve all DNS answers, reject non-public addresses, and pin the connection to a checked address. Redirects are not followed; URL credentials and query parameters are forbidden. Network egress ACLs, trusted DNS, and destination allowlists remain recommended defense in depth.
- The platform binds to loopback by default. If placed behind a reverse proxy, terminate TLS there, restrict direct access to the Node listener, protect database traffic, and never expose HTTP management traffic directly to the Internet. `HOOKLAB_BIND_HOST` can change the listener but does not provide TLS or proxy authentication.
- The PostgreSQL mode has no global tenant quota, cross-instance rate limit, externally managed identity, or automatic migration from SQLite. These remain deployment risks and roadmap items. Consumer delivery is at least once; use the delivery ID as a deduplication key.
- The Compose quickstart binds only to host loopback and is meant for local trials. Its private `.env` holds the database password, encryption key and privileged tokens; it is excluded from Git and Docker build context but still needs restricted host access and separate encrypted backup. The backup verification archive contains event bodies and should not be published. The Compose database role is not a production least-privilege layout.

## Reporting a vulnerability

Do not publish exploitable details in a public issue. Contact the repository maintainer privately with the affected version, reproduction steps, impact, and a proposed mitigation if available. Avoid including real secrets or customer payloads.
