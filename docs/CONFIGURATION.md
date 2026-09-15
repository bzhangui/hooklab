# Gateway configuration

HookLab configuration version 1 moves repeatable gateway settings out of a
long command line while keeping secret values out of the repository. The file
selects one authenticated provider, a loopback port, a state directory, and
one or more content-based delivery routes.

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

Each route has these fields:

| Field | Required | Meaning |
|---|---:|---|
| `name` | yes | Unique operator-facing route name |
| `path` | no | JSON dot path; `$` matches the root and is the default |
| `operator` | yes | `equals`, `not-equals`, `exists`, `contains`, `starts-with`, or `ends-with` |
| `expected` | except `exists` | String compared with the selected scalar value |
| `target` | yes | Trusted HTTP(S) delivery endpoint |

Array indexes are accepted in dot paths, for example `items.0.sku`. If several
routes match, HookLab creates independent delivery work for each distinct
target. A target is never derived from the incoming payload.

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
      "target": "http://127.0.0.1:9091/audit"
    }
  ]
}
~~~

The original `serve` command remains available for quick demonstrations. Use
`serve-config` for a repeatable checked-in deployment definition, after
replacing example targets with endpoints you control.
