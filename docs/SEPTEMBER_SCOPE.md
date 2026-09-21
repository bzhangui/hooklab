# September 2026 maintenance scope

HookLab is submitted as an **existing project maintenance** entry. The public
repository remains:

<https://github.com/bzhangui/hooklab>

## Existing baseline

Commit 548c5e2 is the boundary before the September maintenance work. The
baseline already contained provider verification, pure MoonBit cryptography,
freshness checks, scoped idempotency, routing, redaction, retry decisions,
offline reports, replay tooling, examples, and cross-target tests.

## New substantive work

The September cycle turns the security toolkit into an event-delivery platform:

1. accepted-event domain model and store;
2. explicit delivery lifecycle and deterministic work queue;
3. retry scheduling, dead-letter recovery, cancellation, and ordering keys;
4. Webhook contract validation;
5. gateway orchestration from verified ingress to queued work;
6. persistent runnable local server and management API;
7. safe local dashboard;
8. restart recovery and atomic snapshots;
9. real end-to-end reliability test;
10. operations, security, architecture, and acceptance documentation.

## Post-approval maintenance

After initial review, development continued in the same event-delivery
direction with version 1 declarative gateway configuration, environment-only
secret references, named content routes, CLI validation, and an end-to-end
configured startup test. Development then added per-route deterministic JSON
transformations with mandatory input, output, and operation-count budgets,
atomic failure semantics, stable replay outputs, cross-target tests, and an
end-to-end delivery assertion. Subsequent work added process-local per-target
outbound concurrency and rate controls, a global safety ceiling, and an
end-to-end isolation test. Further maintenance added opt-in per-target circuit
breaking, single half-open probes, process-local anonymized latency histograms,
and an end-to-end recovery test. The next maintenance increment added a pure
MoonBit outbound publication/signature domain, configuration-managed
applications/endpoints/subscriptions, an authenticated idempotent publication
API, SQLite WAL transactions, and fenced Worker leases with crash takeover.
These commits extend the accepted project rather than replacing its subject or
repository.

## Acceptance evidence

| Requirement | Evidence |
|---|---|
| MoonBit is the primary implementation language | hooklab/* domain packages and cmd/hooklab orchestration |
| Public traceable development | Git history after baseline 548c5e2 |
| Runnable software | hooklab serve / serve-config and docs/GATEWAY.md |
| Tests | moon test --target all and eight gateway E2E scripts |
| Reproducible demonstration | scripts/demo.* and gateway E2E test |
| Security boundary | SECURITY.md, redacted APIs, loopback binding |
| Open-source compliance | MIT license and THIRD_PARTY_NOTICES.md |

## AI-assisted development statement

AI tools were used to help analyze interfaces, generate candidate
implementations, and expand tests and documentation. The maintainer remains
responsible for the project scope, technical decisions, source review,
cross-target compilation, security boundaries, and final verification. No
private or closed-source code was used.

## Explicit non-goals for this release

The current release does not claim distributed exactly-once delivery, an
internet-safe multi-tenant control plane, automatic TLS termination,
tenant-controlled endpoint safety, or cross-host PostgreSQL high availability.
SQLite transactions and leases cover the documented single-host deployment;
the remaining items are roadmap work rather than implied capabilities.
