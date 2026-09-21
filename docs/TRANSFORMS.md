# Route transformations

HookLab can transform a verified JSON payload independently for each matched
delivery route. Transformations are deterministic MoonBit operations; they do
not execute scripts, templates, network calls, or expressions supplied by an
incoming webhook.

## Configuration

Add a `transform` object to a route in a version 1 gateway configuration:

~~~json
{
  "name": "billing",
  "path": "kind",
  "operator": "equals",
  "expected": "invoice.paid",
  "target": "https://billing.example.test/hook",
  "transform": {
    "max_input_bytes": 262144,
    "max_output_bytes": 262144,
    "max_operations": 3,
    "operations": [
      {"operation": "copy", "from": "invoice_id", "path": "metadata.invoice_id"},
      {"operation": "remove", "path": "customer.email"},
      {"operation": "set", "path": "source", "value": "hooklab"}
    ]
  }
}
~~~

All three budgets are required when a transform is present:

| Budget | Range | Enforced behavior |
|---|---:|---|
| `max_input_bytes` | 1–1,048,576 | Reject before parsing when the UTF-8 input is larger |
| `max_output_bytes` | 1–1,048,576 | Reject instead of delivering an oversized result |
| `max_operations` | 1–64 | Reject a plan containing more declared operations |

The configuration checker validates every plan before the gateway starts. The
runtime enforces the same budgets for every matched event.

## Operations

Paths use JSON dot notation. `$` means the document root, and array indexes are
numeric components such as `items.0.sku`.

| Operation | Fields | Behavior |
|---|---|---|
| `set` | `path`, `value` | Add or replace a value; parent containers must exist; `$` replaces the root |
| `remove` | `path` | Remove an existing object field or array element; `$` is forbidden |
| `copy` | `from`, `path` | Copy an existing value to a destination whose parent exists |

Operations run in declaration order. A later operation sees the output of the
previous operation.

## Failure and persistence semantics

Signature and freshness verification happen first. HookLab then evaluates
routes and applies every matched transformation before recording idempotency,
persisting the event, or creating delivery work. If one matched plan has
invalid JSON, a missing path, or a budget overrun, the request returns HTTP 422
with `invalid_payload` and no side effects are committed. A provider can retry
the same delivery identifier after the configuration or payload is corrected.

The original authenticated body remains the event source for audit and exact
replay. Each delivery stores its route-specific transformed body in the local
SQLite database. Manual event replay reuses the persisted route-specific
output, so it does not silently change when the current configuration changes.
Older version 1 state files are imported; rows without transformed outputs
replay the original event body.

Raw and transformed bodies are intentionally omitted from management API
responses. Both can exist in the local database, so the configured data
directory must be protected as sensitive material.
