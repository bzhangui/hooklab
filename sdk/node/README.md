# @bzhangui/hooklab-receiver

Zero-dependency Node.js verifier for HookLab outbound webhook deliveries. This
directory is **packable locally**, but has not been published to npm. Do not
claim a registry release until the owner publishes and independently verifies
one.

From the HookLab repository root, run `node scripts/sdk-package-smoke.mjs` to
pack, install into a disposable project, and verify the canonical MoonBit
signature vector. For local application development, use
`npm install ./sdk/node` or install the generated tarball.

```js
const {verifyDelivery} = require('@bzhangui/hooklab-receiver');
const result = verifyDelivery({
  headers: request.headers,
  body: rawBodyBuffer,
  secrets: {[currentKeyId]: currentSecret, [previousKeyId]: previousSecret},
});
if (!result.ok) {
  response.writeHead(401);
  response.end();
  return;
}
// Commit a durable (consumer ID, delivery ID) dedup key and business update
// in one transaction before returning a 2xx response.
```

Pass the **original bytes** before JSON parsing, set a bounded body size, and
keep secrets outside source code. The default timestamp window is ±300 seconds;
the receiver clock must be synchronized. `verifyDelivery` reports
`invalid_headers`, `stale_timestamp`, `unknown_key`, or `invalid_signature`.
Avoid exposing the exact reason to callers. Verification is not deduplication:
HookLab uses at-least-once delivery. See the repository's
[`docs/RECEIVER.md`](https://github.com/bzhangui/hooklab/blob/main/docs/RECEIVER.md)
for a durable example and security boundary.
