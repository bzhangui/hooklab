# Gateway configuration

HookLab configuration version 1 moves repeatable gateway settings out of a
long command line while keeping secret values out of the repository. The file
selects one authenticated provider, a loopback port, a state directory, and
one or more content-based delivery routes. A route may also define a bounded,
deterministic JSON transformation.

## Validate before starting

~~~bash
moon run --target js cmd/hooklab -- config-check examples/gateway/config.json
~~~

A valid file prints a safe JSON summary and exits with status 0. An invalid
file returns every detected issue with a stable code and field location, so it
can be checked in CI without starting a server.

## Start from configuration

Set secret values in the environment. The configuration contains only the
names of those variables:

~~~bash
export HOOKLAB_SECRET=replace-with-a-secret
export HOOKLAB_PREVIOUS_SECRETS=replace-with-the-previous-secret
moon run --target js cmd/hooklab -- serve-config examples/gateway/config.json
~~~

PowerShell:

~~~powershell
$env:HOOKLAB_SECRET = "replace-with-a-secret"
$env:HOOKLAB_PREVIOUS_SECRETS = "replace-with-the-previous-secret"
moon run --target js cmd/hooklab -- serve-config examples/gateway/config.json
~~~

Do not commit a real secret. A file containing `secret` or `secrets` is
rejected even if the rest of the configuration is valid.

## Version 1 schema

| Field | Required | Meaning |
|---|---:|---|
| `version` | yes | Must be `1` |
| `provider` | yes | `github`, `stripe`, `feishu`, or `generic-hmac` |
| `secret_env` | no | Primary secret variable; defaults to `HOOKLAB_SECRET` |
| `previous_secrets_env` | no | Rotated secrets variable; defaults to `HOOKLAB_PREVIOUS_SECRETS`; use `null` to disable |
| `port` | no | Loopback port from 1 through 65535; defaults to 8787 |
| `data_dir` | no | Persistent state directory; defaults to `.hooklab-data` |
| `routes` | yes | Non-empty array of unique named routes |
| `delivery_limits` | no | Per-target outbound concurrency and rate policies |
| `circuit_breakers` | no | Opt-in per-target failure circuit policies |

Each route has these fields:

| Field | Required | Meaning |
|---|---:|---|
| `name` | yes | Unique operator-facing route name |
| `path` | no | JSON dot path; `$` matches the root and is the default |
| `operator` | yes | `equals`, `not-equals`, `exists`, `contains`, `starts-with`, or `ends-with` |
| `expected` | except `exists` | String compared with the selected scalar value |
| `target` | yes | Trusted HTTP(S) delivery endpoint |
| `transform` | no | Route-specific set/remove/copy plan with mandatory budgets |

Array indexes are accepted in dot paths, for example `items.0.sku`. If several
routes match, HookLab creates independent delivery work for each distinct
target. A target is never derived from the incoming payload.

## Outbound delivery limits

Each optional `delivery_limits` entry selects an exact HTTP(S) `target` used by
at least one route, a required `max_concurrency` from 1 through 16, and an
optional `requests_per_second` from 1 through 100. A target can appear only
once. The request rate counts started attempts in a rolling one-second window;
retries and manual replays use the same limit. An omitted rate has no rate cap.
Targets without a policy default to one in-flight attempt and no rate cap.
The process also has a hard ceiling of 16 simultaneous outbound attempts.

The counters live in one gateway process and reset after restart. They are not
a distributed quota; multi-instance deployments need external coordination.
Admission never changes an accepted event into a rejection: pending deliveries
wait until a slot or rate window opens. See [GATEWAY.md](GATEWAY.md) for delivery
behavior and operational boundaries.

## Opt-in circuit breakers

Each optional `circuit_breakers` entry names an exact HTTP(S) `target` present
in `routes`, a `failure_threshold` from 1 through 20 retryable failures
since the last success, and an `open_ms` cooldown from 1000 through 300000
milliseconds. Permanent responses do not change the failure count.
Targets must be unique. Omit this field to preserve the previous behavior:
no circuit breaker is active. A configured circuit opens after transport
errors or HTTP 408, 425, 429, or 5xx; permanent HTTP 4xx does not trip it.
After cooldown, only one half-open probe may run. A success closes the circuit;
a retryable failure reopens it. Pending work waits without consuming an attempt
or rate token. The state is process-local and resets after restart.

## Bounded route transforms

A route may transform its delivery body after signature verification. Every
transform must declare `max_input_bytes`, `max_output_bytes`, and
`max_operations`; plans without explicit budgets are rejected during
`config-check`. Supported operations are `set`, `remove`, and `copy`.

Transformations complete before idempotency and persistence. A missing path,
invalid JSON document, or budget overrun rejects the whole request without
creating an event or delivery. See [TRANSFORMS.md](TRANSFORMS.md) for the
complete schema, failure behavior, replay semantics, and security boundary.

## Example

~~~json
{
  "version": 1,
  "provider": "generic-hmac",
  "secret_env": "HOOKLAB_SECRET",
  "previous_secrets_env": "HOOKLAB_PREVIOUS_SECRETS",
  "port": 8787,
  "data_dir": ".hooklab-data",
  "routes": [
    {
      "name": "paid-invoices",
      "path": "kind",
      "operator": "equals",
      "expected": "invoice.paid",
      "target": "http://127.0.0.1:9090/billing"
    },
    {
      "name": "audit-all",
      "path": "$",
      "operator": "exists",
      "target": "http://127.0.0.1:9091/audit",
      "transform": {
        "max_input_bytes": 262144,
        "max_output_bytes": 262144,
        "max_operations": 1,
        "operations": [
          {"operation": "set", "path": "hooklab_route", "value": "audit-all"}
        ]
      }
    }
  ],
  "delivery_limits": [
    {
      "target": "http://127.0.0.1:9090/billing",
      "max_concurrency": 2,
      "requests_per_second": 5
    }
  ],
  "circuit_breakers": [
    {
      "target": "http://127.0.0.1:9090/billing",
      "failure_threshold": 3,
      "open_ms": 10000
    }
  ]
}
~~~

The original `serve` command remains available for quick demonstrations. Use
`serve-config` for a repeatable checked-in deployment definition, after
replacing example targets with endpoints you control.
