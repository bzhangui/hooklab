# Contributing

Keep provider adapters small and backed by official protocol documentation and deterministic test vectors. Any new verification path must include success, tampered-body, malformed-signature, and replay/freshness tests where applicable.

Before submitting a change, run:

```bash
node scripts/check-moonc-version.mjs
node scripts/check-toolchain-lock.mjs
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
npm run test:platform:coverage
```

Changes go through a pull request with the five CI jobs passing. GitHub Actions
are pinned to commit SHAs; Dependabot proposes updates to both npm dependencies
and actions, and each update must pass CI before merge. Do not treat a green
synthetic repeatability run as an external pilot or production SLO.
The CI toolchain version gate deliberately fails if the upstream installer
changes its output; review the release notes, update
`scripts/check-toolchain-lock.mjs`, and rerun all jobs before merging. This is
a version-drift gate rather than a vendored or checksum-pinned toolchain.
Node coverage applies only to `admission.cjs`, `core.cjs`, `migrations.cjs` and
`retention.cjs`; server and worker paths require the separate PostgreSQL and
Compose E2E jobs. Never report the helper floor as whole-platform coverage.

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
