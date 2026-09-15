# Contributing

Keep provider adapters small and backed by official protocol documentation and deterministic test vectors. Any new verification path must include success, tampered-body, malformed-signature, and replay/freshness tests where applicable.

Before submitting a change, run:

```bash
moon info
moon fmt
moon check --target all --deny-warn
moon test --target all
moon build --target all --deny-warn
node scripts/gateway-e2e.mjs
node scripts/gateway-config-e2e.mjs
node scripts/gateway-deadletter-e2e.mjs
node scripts/gateway-restart-e2e.mjs
```

Never commit provider secrets or real webhook payloads. Fixtures must use obvious test-only values and should be passed through the redaction policy.
