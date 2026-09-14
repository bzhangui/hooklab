import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function unusedPort() {
  const server = http.createServer();
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port;
}
async function waitFor(url, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
      if (response.ok) return;
    } catch (_) {}
    await sleep(100);
  }
  throw new Error("Timed out waiting for " + url);
}

const gatewayPort = await unusedPort();
const receiverPort = await unusedPort();
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "hooklab-deadletter-"));
let acceptDelivery = false;
const receiver = http.createServer((_req, res) => {
  if (acceptDelivery) res.writeHead(204);
  else res.writeHead(400);
  res.end();
});
await new Promise(resolve => receiver.listen(receiverPort, "127.0.0.1", resolve));
const child = spawn(
  process.platform === "win32" ? "moon.exe" : "moon",
  [
    "run", "--target", "js", "cmd/hooklab", "--", "serve", "generic",
    "deadletter-secret", "http://127.0.0.1:" + receiverPort + "/target",
    String(gatewayPort), dataDir,
  ],
  {cwd: path.resolve(import.meta.dirname, ".."), stdio: "ignore"},
);

try {
  await waitFor("http://127.0.0.1:" + gatewayPort + "/health");
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const body = JSON.stringify({kind: "recovery.test"});
  const signature = crypto.createHmac("sha256", "deadletter-secret")
    .update(timestamp + "." + body)
    .digest("hex");
  const response = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/hooks/generic",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-webhook-signature": "sha256=" + signature,
        "x-webhook-timestamp": timestamp,
        "x-webhook-id": "deadletter-event-1",
        "x-webhook-event": "recovery.test",
      },
      body,
    },
  );
  assert.equal(response.status, 202);
  let delivery;
  const deadDeadline = Date.now() + 5000;
  while (Date.now() < deadDeadline) {
    const rows = await fetch(
      "http://127.0.0.1:" + gatewayPort + "/api/deliveries",
    ).then(value => value.json());
    delivery = rows[0];
    if (delivery?.state === "dead_lettered") break;
    await sleep(100);
  }
  assert.equal(delivery?.state, "dead_lettered");
  assert.equal(delivery?.attempt, 1);

  acceptDelivery = true;
  const retry = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/api/deliveries/" +
      encodeURIComponent(delivery.id) + "/retry",
    {method: "POST"},
  );
  assert.equal(retry.status, 202);
  const recoveryDeadline = Date.now() + 5000;
  while (Date.now() < recoveryDeadline) {
    const rows = await fetch(
      "http://127.0.0.1:" + gatewayPort + "/api/deliveries",
    ).then(value => value.json());
    delivery = rows[0];
    if (delivery?.state === "delivered") break;
    await sleep(100);
  }
  assert.equal(delivery?.state, "delivered");
  assert.equal(delivery?.attempt, 1);
  console.log("Gateway dead-letter recovery E2E passed.");
} finally {
  child.kill();
  await new Promise(resolve => receiver.close(resolve));
  await sleep(200);
  if (path.resolve(dataDir).startsWith(path.resolve(os.tmpdir()))) {
    fs.rmSync(dataDir, {recursive: true, force: true});
  }
}
