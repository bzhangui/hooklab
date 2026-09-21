import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
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

async function requestStatus({port, path: requestPath, method = "GET", headers}) {
  return await new Promise((resolve, reject) => {
    const request = http.request({
      hostname: "127.0.0.1",
      port,
      path: requestPath,
      method,
      headers,
    }, response => {
      response.resume();
      response.on("end", () => resolve(response.statusCode));
    });
    request.on("error", reject);
    request.end();
  });
}

const root = path.resolve(import.meta.dirname, "..");
const gatewayPort = await unusedPort();
const receiverPort = await unusedPort();
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "hooklab-config-"));
const stateDir = path.join(dataDir, "state");
const configPath = path.join(dataDir, "gateway.json");
const target = "http://127.0.0.1:" + receiverPort + "/billing";
fs.writeFileSync(
  configPath,
  JSON.stringify({
    version: 1,
    provider: "generic-hmac",
    secret_env: "HOOKLAB_CONFIG_SECRET",
    previous_secrets_env: null,
    port: gatewayPort,
    data_dir: stateDir,
    routes: [
      {
        name: "paid-invoices",
        path: "kind",
        operator: "equals",
        expected: "invoice.paid",
        target,
        transform: {
          max_input_bytes: 4096,
          max_output_bytes: 4096,
          max_operations: 3,
          operations: [
            {operation: "copy", from: "invoice_id", path: "metadata.invoice_id"},
            {operation: "remove", path: "customer.email"},
            {operation: "set", path: "source", value: "hooklab"},
          ],
        },
      },
    ],
  }),
  "utf8",
);

const moon = process.platform === "win32" ? "moon.exe" : "moon";
const checked = spawnSync(
  moon,
  ["run", "--target", "js", "cmd/hooklab", "--", "config-check", configPath],
  {cwd: root, encoding: "utf8"},
);
assert.equal(checked.status, 0, checked.stderr);
const summary = JSON.parse(checked.stdout.trim().split(/\r?\n/).at(-1));
assert.equal(summary.valid, true);
assert.equal(summary.routes, 1);
assert.equal(summary.transforms, 1);

let received = 0;
const receivedPayloads = [];
const receiver = http.createServer((req, res) => {
  const chunks = [];
  req.on("data", chunk => chunks.push(chunk));
  req.on("end", () => {
    received++;
    receivedPayloads.push(JSON.parse(Buffer.concat(chunks).toString("utf8")));
    res.writeHead(204);
    res.end();
  });
});
await new Promise(resolve => receiver.listen(receiverPort, "127.0.0.1", resolve));

const child = spawn(
  moon,
  ["run", "--target", "js", "cmd/hooklab", "--", "serve-config", configPath],
  {
    cwd: root,
    stdio: "ignore",
    env: {...process.env, HOOKLAB_CONFIG_SECRET: "config-secret"},
    detached: process.platform !== "win32",
  },
);

try {
  await waitFor(
    "http://127.0.0.1:" + gatewayPort + "/health",
    value => value.status === "ok",
  );
  const base = "http://127.0.0.1:" + gatewayPort;
  const foreignHostStatus = await requestStatus({
    port: gatewayPort,
    path: "/health",
    headers: {host: "attacker.example"},
  });
  assert.equal(foreignHostStatus, 421);
  const malformedHook = await fetch(base + "/hooks/%", {method: "POST"});
  assert.equal(malformedHook.status, 400);
  const healthAfterMalformedHook = await fetch(base + "/health");
  assert.equal(healthAfterMalformedHook.status, 200);
  assert.equal((await healthAfterMalformedHook.json()).status, "ok");

  const send = (id, body) => {
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const signature = crypto.createHmac("sha256", "config-secret")
      .update(timestamp + "." + body)
      .digest("hex");
    return fetch(
      "http://127.0.0.1:" + gatewayPort + "/hooks/generic-hmac",
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-webhook-signature": "sha256=" + signature,
          "x-webhook-timestamp": timestamp,
          "x-webhook-id": id,
          "x-webhook-event": "invoice.paid",
        },
        body,
      },
    );
  };
  const rejectedBody = JSON.stringify({
    kind: "invoice.paid",
    invoice_id: "inv-rejected",
    customer: {},
    metadata: {},
  });
  const rejected = await send("configured-rejected-1", rejectedBody);
  assert.equal(rejected.status, 422);
  assert.equal((await rejected.json()).code, "invalid_payload");
  const emptyStats = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/api/stats",
  ).then(response => response.json());
  assert.equal(emptyStats.events, 0);
  assert.equal(emptyStats.pending, 0);

  const body = JSON.stringify({
    kind: "invoice.paid",
    invoice_id: "inv-config-1",
    amount: 4200,
    customer: {email: "private@example.test"},
    metadata: {},
  });
  const accepted = await send("configured-event-1", body);
  assert.equal(accepted.status, 202);
  const acceptance = await accepted.json();
  assert.equal(acceptance.deliveries, 1);

  const deliveries = await waitFor(
    "http://127.0.0.1:" + gatewayPort + "/api/deliveries",
    value => value[0]?.state === "delivered",
  );
  assert.equal(deliveries[0].target, target);
  assert.equal(received, 1);
  const expectedPayload = {
    kind: "invoice.paid",
    invoice_id: "inv-config-1",
    amount: 4200,
    customer: {},
    metadata: {invoice_id: "inv-config-1"},
    source: "hooklab",
  };
  assert.deepEqual(receivedPayloads[0], expectedPayload);

  const events = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/api/events",
  ).then(response => response.json());
  const replayUrl = "http://127.0.0.1:" + gatewayPort + "/api/events/" +
    encodeURIComponent(events[0].id) + "/replay";
  const malformedReplay = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/api/events/%/replay",
    {method: "POST"},
  );
  assert.equal(malformedReplay.status, 400);
  const crossOriginReplay = await fetch(replayUrl, {
    method: "POST",
    headers: {origin: "https://attacker.example"},
  });
  assert.equal(crossOriginReplay.status, 403);
  const unchangedDeliveries = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/api/deliveries",
  ).then(response => response.json());
  assert.equal(unchangedDeliveries.length, 1);
  assert.equal(received, 1);
  const healthAfterRejectedReplay = await fetch(base + "/health");
  assert.equal(healthAfterRejectedReplay.status, 200);
  assert.equal((await healthAfterRejectedReplay.json()).status, "ok");

  const replay = await fetch(
    replayUrl,
    {method: "POST"},
  );
  assert.equal(replay.status, 202);
  assert.equal((await replay.json()).replayed, 1);
  await waitFor(
    "http://127.0.0.1:" + gatewayPort + "/api/deliveries",
    value => value.length === 2 && value.every(item => item.state === "delivered"),
  );
  assert.equal(received, 2);
  assert.deepEqual(receivedPayloads[1], expectedPayload);
  assert.equal(fs.existsSync(path.join(stateDir, "hooklab.sqlite")), true);
  console.log("Gateway declarative configuration E2E passed.");
} finally {
  await stopChild(child);
  await new Promise(resolve => receiver.close(resolve));
  if (path.resolve(dataDir).startsWith(path.resolve(os.tmpdir()))) {
    fs.rmSync(dataDir, {recursive: true, force: true});
  }
}
