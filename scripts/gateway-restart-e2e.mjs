import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { stopChild } from "./e2e-process.mjs";

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function unusedPort() {
  const server = http.createServer();
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port;
}
async function waitFor(url, predicate, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
      if (response.ok) {
        const value = await response.json();
        if (predicate(value)) return value;
      }
    } catch (_) {}
    await sleep(100);
  }
  throw new Error("Timed out waiting for " + url);
}

const gatewayPort = await unusedPort();
const receiverPort = await unusedPort();
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "hooklab-restart-"));
const target = "http://127.0.0.1:" + receiverPort + "/target";
let received = 0;
const receiver = http.createServer((_req, res) => {
  received++;
  res.writeHead(204);
  res.end();
});
await new Promise(resolve => receiver.listen(receiverPort, "127.0.0.1", resolve));
const now = Date.now();
fs.writeFileSync(
  path.join(dataDir, "state.json"),
  JSON.stringify({
    version: 1,
    events: [{
      id: "generic-hmac:persistent-1",
      provider: "generic-hmac",
      eventType: "restart.test",
      deliveryId: "persistent-1",
      body: "{\"ok\":true}",
      redactedBody: "{\n  \"ok\": true\n}",
      headers: [],
      receivedAt: now,
      targets: [target],
    }],
    deliveries: [{
      id: "delivery:restart-1",
      eventId: "generic-hmac:persistent-1",
      target,
      state: "in_flight",
      attempt: 1,
      nextAttemptAt: now,
      lastStatus: null,
      lastError: null,
      createdAt: now,
      updatedAt: now,
    }],
  }),
  "utf8",
);

const child = spawn(
  process.platform === "win32" ? "moon.exe" : "moon",
  [
    "run", "--target", "js", "cmd/hooklab", "--", "serve", "generic",
    "-", target, String(gatewayPort), dataDir,
  ],
  {
    cwd: path.resolve(import.meta.dirname, ".."),
    stdio: "ignore",
    env: {...process.env, HOOKLAB_SECRET: "restart-secret"},
    detached: process.platform !== "win32",
  },
);
try {
  const rows = await waitFor(
    "http://127.0.0.1:" + gatewayPort + "/api/deliveries",
    value => value[0]?.state === "delivered",
  );
  assert.equal(rows[0].attempt, 2);
  assert.equal(received, 1);

  const timestamp = Math.floor(Date.now() / 1000).toString();
  const body = "{\"ok\":true}";
  const signature = crypto.createHmac("sha256", "restart-secret")
    .update(timestamp + "." + body)
    .digest("hex");
  const duplicate = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/hooks/generic",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-webhook-signature": "sha256=" + signature,
        "x-webhook-timestamp": timestamp,
        "x-webhook-id": "persistent-1",
        "x-webhook-event": "restart.test",
      },
      body,
    },
  );
  assert.equal(duplicate.status, 200);
  const result = await duplicate.json();
  assert.equal(result.duplicate, true);
  await sleep(500);
  assert.equal(received, 1);
  console.log("Gateway restart recovery and persistent deduplication E2E passed.");
} finally {
  await stopChild(child);
  await new Promise(resolve => receiver.close(resolve));
  await sleep(200);
  if (path.resolve(dataDir).startsWith(path.resolve(os.tmpdir()))) {
    fs.rmSync(dataDir, {recursive: true, force: true});
  }
}
