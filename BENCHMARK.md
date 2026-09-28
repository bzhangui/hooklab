# Benchmarks

Benchmarks are evidence for regression detection, not a claim about production
HTTP throughput.

## Route evaluation

The bundled benchmark parses a representative nested JSON event and evaluates
three routing rules, including an array path.

~~~bash
moon bench --target native --release -p bzhangui/hooklab/hooklab/engine
~~~

Local reference run on 14 September 2026:

| Environment | Mean | Range |
|---|---:|---:|
| AMD Ryzen 7 8845H, MoonBit 0.1.20260703, native release | 3.37 µs | 3.33–3.40 µs |

The exact value depends on hardware and toolchain version. Future optimization
changes should compare on the same machine and retain matching routing tests.

## Synthetic platform evidence

`TEST_DATABASE_URL=... node scripts/platform-showcase.mjs` uses a dedicated
PostgreSQL test database, two local application instances, a signed loopback
receiver, forced Worker termination and 32 synthetic events. It asserts that
the receiver verifies signatures, that the failover retry has the same
delivery ID but only one unique accepted consumer ID, and that the batch
reaches `delivered`. It reports per-request p50/p95 and batch completion time.
The report is a single-run regression sample, not a steady-state throughput,
long-soak, external-network latency, or production SLO measurement. Compare
numbers only on matched hardware, PostgreSQL, Node.js and MoonBit versions.
No long-duration or authorized real-user performance result exists yet.

## Bounded repeated synthetic acceptance

The [multi-persona runner](docs/SIMULATED_PILOT.md) can repeat its dedicated
PostgreSQL scenario up to 30 times. Each round checks tenant isolation,
cross-instance quotas and forced-worker failover, then records only whitelisted
synthetic timing numbers in `target/simulated-pilot-report.json`. The public CI
uses three rounds. Compare p50/p95 only between matching CI runner, toolchain,
database and revision; repeated loopback results still do not establish a
production SLO, external-network latency or long-duration soak capacity.
