import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import {spawn} from "node:child_process";
import {stopChild} from "./e2e-process.mjs";

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
  let last;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
      if (response.ok) {
        const value = await response.json();
        if (predicate(value)) return value;
      }
    } catch (error) { last = error; }
    await sleep(100);
  }
  throw new Error("Timed out waiting for " + url + ": " + String(last));
}

const root = path.resolve(import.meta.dirname, "..");
const gatewayPort = await unusedPort();
const receiverPort = await unusedPort();
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "hooklab-lease-"));
const target = "http://127.0.0.1:" + receiverPort + "/target";
let received = 0;
let renewedReceived = 0;
const hangingResponses = [];

const receiver = http.createServer((req, res) => {
  const eventId = req.headers["x-hooklab-event-id"];
  req.resume();
  req.on("end", () => {
    received++;
    if (eventId === "generic-hmac:lease-event-1" && received === 1) {
      hangingResponses.push(res);
      return;
    }
    if (eventId === "generic-hmac:renew-event-2") {
      renewedReceived++;
      setTimeout(() => {
        try { res.writeHead(204); res.end(); } catch (_) {}
      }, 1500);
      return;
    }
    res.writeHead(204);
    res.end();
  });
});
await new Promise(resolve => receiver.listen(receiverPort, "127.0.0.1", resolve));

const moon = process.platform === "win32" ? "moon.exe" : "moon";
const args = [
  "run", "--target", "js", "cmd/hooklab", "--", "serve", "generic", "-",
  target, String(gatewayPort), dataDir,
];
const spawnGateway = () => spawn(moon, args, {
  cwd: root,
  stdio: "ignore",
  env: {
    ...process.env,
    HOOKLAB_SECRET: "lease-secret",
    HOOKLAB_LEASE_MS: "1000",
  },
  detached: process.platform !== "win32",
});

let first = spawnGateway();
let second;
try {
  const firstHealth = await waitFor(
    "http://127.0.0.1:" + gatewayPort + "/health",
    value => value.status === "ok",
  );
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const body = JSON.stringify({kind: "lease.test"});
  const signature = crypto.createHmac("sha256", "lease-secret")
    .update(timestamp + "." + body)
    .digest("hex");
  const accepted = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/hooks/generic",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-webhook-signature": "sha256=" + signature,
        "x-webhook-timestamp": timestamp,
        "x-webhook-id": "lease-event-1",
        "x-webhook-event": "lease.test",
      },
      body,
    },
  );
  assert.equal(accepted.status, 202);
  const inFlight = await waitFor(
    "http://127.0.0.1:" + gatewayPort + "/api/deliveries",
    value => value[0]?.state === "in_flight" && value[0]?.leasedUntil > Date.now(),
  );
  assert.equal(inFlight[0].attempt, 1);
  assert.equal(inFlight[0].leaseOwner, firstHealth.workerId);

  await stopChild(first);
  first = null;
  await sleep(200);
  second = spawnGateway();
  const secondHealth = await waitFor(
    "http://127.0.0.1:" + gatewayPort + "/health",
    value => value.status === "ok" && value.workerId !== firstHealth.workerId,
  );
  assert.notEqual(secondHealth.workerId, firstHealth.workerId);
  const delivered = await waitFor(
    "http://127.0.0.1:" + gatewayPort + "/api/deliveries",
    value => value[0]?.state === "delivered",
    10000,
  );
  assert.equal(delivered[0].attempt, 2);
  assert.equal(delivered[0].leaseOwner, null);
  assert.equal(received, 2);

  const renewalTimestamp = Math.floor(Date.now() / 1000).toString();
  const renewalBody = JSON.stringify({kind: "lease.renewal"});
  const renewalSignature = crypto.createHmac("sha256", "lease-secret")
    .update(renewalTimestamp + "." + renewalBody)
    .digest("hex");
  const renewalAccepted = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/hooks/generic",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-webhook-signature": "sha256=" + renewalSignature,
        "x-webhook-timestamp": renewalTimestamp,
        "x-webhook-id": "renew-event-2",
        "x-webhook-event": "lease.renewal",
      },
      body: renewalBody,
    },
  );
  assert.equal(renewalAccepted.status, 202);
  const renewalDelivered = await waitFor(
    "http://127.0.0.1:" + gatewayPort + "/api/deliveries",
    value => value.find(item => item.eventId === "generic-hmac:renew-event-2")?.state === "delivered",
    10000,
  );
  const renewalRow = renewalDelivered.find(
    item => item.eventId === "generic-hmac:renew-event-2",
  );
  assert.equal(renewalRow.attempt, 1);
  assert.equal(renewedReceived, 1);
  assert.equal(received, 3);
  assert.equal(fs.existsSync(path.join(dataDir, "hooklab.sqlite")), true);
  console.log("Gateway lease E2E passed: crash recovery reclaimed an expired lease, while renewal kept a slow active delivery single-attempt.");
} finally {
  if (first) await stopChild(first);
  if (second) await stopChild(second);
  for (const response of hangingResponses) {
    try { response.destroy(); } catch (_) {}
  }
  await new Promise(resolve => receiver.close(resolve));
  await sleep(200);
  if (path.resolve(dataDir).startsWith(path.resolve(os.tmpdir()))) {
    fs.rmSync(dataDir, {recursive: true, force: true});
  }
}
