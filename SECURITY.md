# Security policy and threat model

## Threats addressed

HookLab is designed to reduce forged webhooks, stale-event replay, duplicate side effects, sensitive diagnostic leakage, unbounded delivery retry, and unsafe HTML report rendering.

The implementation validates signature syntax and compares fixed-length digests without early exit. Timestamp checks reject stale and implausibly future events. Idempotency is evaluated only after authentication. Default redaction traverses nested JSON and covers common credential and personal-data keys. Offline HTML escapes all untrusted content and contains no script or remote asset.

## Boundaries and residual risks

- The included idempotency store is process-local. Distributed deployments require transactional shared storage.
- Constant-time comparison reduces timing leakage in digest comparison, but a managed runtime and surrounding application can still introduce side channels. Do not expose detailed timing measurements.
- CLI secrets can be visible in shell history and process listings. Use library integration and a secret manager in production.
- HTTP replay sends data to a user-selected URL and follows the runtime's network behavior. Use only isolated, authorized endpoints; apply outbound allowlists in production.
- Payload size limits, ingress rate limits, TLS termination, SSRF controls, tenant isolation, and secret rotation are deployment responsibilities.
- Redaction is key-based and cannot recognize every sensitive value. Configure additional field names for domain-specific data.

## Reporting a vulnerability

Do not publish exploitable details in a public issue. Contact the repository maintainer privately with the affected version, reproduction steps, impact, and a proposed mitigation if available. Avoid including real secrets or customer payloads.
