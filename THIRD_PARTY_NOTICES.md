# Third-party notices and references

HookLab's MoonBit core has no third-party runtime package dependency. The single-node JavaScript gateway uses Node.js built-in modules, including `node:sqlite`. The PostgreSQL platform adapter uses the npm packages `pg` (MIT) and `ipaddr.js` (MIT). Tests additionally use `@electric-sql/pglite` (Apache-2.0). Dependencies are installed from the lockfile, not vendored into this repository. HookLab source is distributed under the MIT License in [LICENSE](LICENSE).

The lockfile's direct and transitive npm package license metadata is checked by `node scripts/check-dependency-licenses.mjs` in CI. The currently reviewed set is MIT, ISC and Apache-2.0. This is a change-detection gate, not a substitute for reviewing the actual license texts and notices when dependencies change.

Protocol behavior was implemented from public specifications and documentation; no provider SDK source code was copied:

- GitHub, “Validating webhook deliveries”: https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries
- Stripe, “Receive Stripe events in your webhook endpoint”: https://docs.stripe.com/webhooks
- Feishu Open Platform, request signature verification: https://open.feishu.cn/document/server-docs/event-subscription-guide/event-subscription-configure-/encrypt-key-encryption-configuration-case
- NIST FIPS PUB 180-4, Secure Hash Standard (SHA-256)
- RFC 2104 / RFC 4231, HMAC definition and test vectors
- RFC 9110, Retry-After response semantics
- CloudEvents 1.0 specification: https://github.com/cloudevents/spec/blob/main/cloudevents/spec.md
- PostgreSQL row locking / SKIP LOCKED: https://www.postgresql.org/docs/current/sql-select.html

Example payloads, identifiers, secrets and destinations in this repository are synthetic and reserved for testing. They contain no customer data or production credentials.
