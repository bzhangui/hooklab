# Contributing

Keep provider adapters small and backed by official protocol documentation and deterministic test vectors. Any new verification path must include success, tampered-body, malformed-signature, and replay/freshness tests where applicable.

Before submitting a change, run:

```bash
node scripts/check-moonc-version.mjs
moon info
moon fmt
moon check --target all --deny-warn
moon test --target all
moon build --target all --deny-warn
node scripts/check-package-contents.mjs
node scripts/gateway-e2e.mjs
node scripts/gateway-config-e2e.mjs
node scripts/gateway-deadletter-e2e.mjs
node scripts/gateway-restart-e2e.mjs
node scripts/gateway-limits-e2e.mjs
node scripts/gateway-circuit-e2e.mjs
node scripts/gateway-outbound-e2e.mjs
node scripts/gateway-lease-e2e.mjs
npm run test:platform
```

Changes to PostgreSQL schema or retention must also test both fresh setup and
v1-to-current migration, keep existing data intact, document backup/rollback
requirements, and never run deletion against a shared database. The PostgreSQL
integration and Compose recovery checks run in CI; local execution requires a
dedicated `hooklab_test` database or disposable Compose volumes.

Never commit provider secrets or real webhook payloads. Fixtures must use obvious test-only values and should be passed through the redaction policy.

For registry releases, inspect `moon package --list --frozen` before publishing.
The `.moonignore` file is the archive boundary and must retain the private-file
rules from `.gitignore` as well as the application-material exclusion. Do not
publish from a working tree containing unpublished private edits until the
archive checker passes. Registry account setup and verification are documented
in [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md).
