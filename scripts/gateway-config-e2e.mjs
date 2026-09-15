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

let received = 0;
const receiver = http.createServer((_req, res) => {
  received++;
  res.writeHead(204);
  res.end();
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
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const body = JSON.stringify({kind: "invoice.paid", amount: 4200});
  const signature = crypto.createHmac("sha256", "config-secret")
    .update(timestamp + "." + body)
    .digest("hex");
  const accepted = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/hooks/generic-hmac",
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-webhook-signature": "sha256=" + signature,
        "x-webhook-timestamp": timestamp,
        "x-webhook-id": "configured-event-1",
        "x-webhook-event": "invoice.paid",
      },
      body,
    },
  );
  assert.equal(accepted.status, 202);
  const acceptance = await accepted.json();
  assert.equal(acceptance.deliveries, 1);

  const deliveries = await waitFor(
    "http://127.0.0.1:" + gatewayPort + "/api/deliveries",
    value => value[0]?.state === "delivered",
  );
  assert.equal(deliveries[0].target, target);
  assert.equal(received, 1);
  assert.equal(fs.existsSync(path.join(stateDir, "state.json")), true);
  console.log("Gateway declarative configuration E2E passed.");
} finally {
  await stopChild(child);
  await new Promise(resolve => receiver.close(resolve));
  if (path.resolve(dataDir).startsWith(path.resolve(os.tmpdir()))) {
    fs.rmSync(dataDir, {recursive: true, force: true});
  }
}
