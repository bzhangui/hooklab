# Webhook contracts

The hooklab/contract package adds a transport-independent acceptance contract on
top of signature verification. A contract can require:

- a specific provider;
- an event type;
- required HTTP headers;
- required nested JSON paths, including array indexes;
- a maximum request-body size.

Validation returns every discovered issue rather than stopping at the first
one. Stable codes include provider_mismatch, event_type_mismatch,
missing_header, missing_path, body_too_large, and invalid_json.

Contracts do not replace provider authentication. The intended order is:

~~~text
signature and freshness
  -> idempotency
  -> contract validation
  -> persistence and routing
~~~

JSON Schema is intentionally not reimplemented. Applications that require full
schema semantics should integrate a maintained MoonBit JSON Schema package and
keep HookLab contracts for transport and event-envelope requirements.
