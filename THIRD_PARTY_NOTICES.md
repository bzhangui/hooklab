# Third-party notices and references

HookLab's MoonBit core currently has no third-party runtime package dependency. The repository is distributed under the MIT License.

Protocol behavior was implemented from public specifications and documentation; no provider SDK source code was copied:

- GitHub, “Validating webhook deliveries”: https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries
- Stripe, “Receive Stripe events in your webhook endpoint”: https://docs.stripe.com/webhooks
- Feishu Open Platform, request signature verification: https://open.feishu.cn/document/server-docs/event-subscription-guide/event-subscription-configure-/encrypt-key-encryption-configuration-case
- NIST FIPS PUB 180-4, Secure Hash Standard (SHA-256)
- RFC 2104 / RFC 4231, HMAC definition and test vectors

Example payloads, identifiers, secrets and destinations in this repository are synthetic and reserved for testing. They contain no customer data or production credentials.
