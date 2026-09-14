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

async function waitFor(url, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  let last;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
      if (response.ok) return response;
      last = new Error("HTTP " + response.status);
    } catch (error) {
      last = error;
    }
    await sleep(100);
  }
  throw new Error("Timed out waiting for " + url + ": " + String(last));
}

const gatewayPort = await unusedPort();
const receiverPort = await unusedPort();
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "hooklab-e2e-"));
let attempts = 0;
const receiver = http.createServer((req, res) => {
  const chunks = [];
  req.on("data", chunk => chunks.push(chunk));
  req.on("end", () => {
    attempts++;
    if (attempts < 3) {
      res.writeHead(503, {"retry-after": "0"});
      res.end("temporarily unavailable");
    } else {
      res.writeHead(204);
      res.end();
    }
  });
});
await new Promise(resolve => receiver.listen(receiverPort, "127.0.0.1", resolve));

const moon = process.platform === "win32" ? "moon.exe" : "moon";
const child = spawn(
  moon,
  [
    "run",
    "--target",
    "js",
    "cmd/hooklab",
    "--",
    "serve",
    "generic",
    "e2e-secret",
    "http://127.0.0.1:" + receiverPort + "/target",
    String(gatewayPort),
    dataDir,
  ],
  {
    cwd: path.resolve(import.meta.dirname, ".."),
    stdio: ["ignore", "pipe", "pipe"],
    detached: process.platform !== "win32",
  },
);
let logs = "";
child.stdout.on("data", chunk => { logs += chunk; });
child.stderr.on("data", chunk => { logs += chunk; });

try {
  await waitFor("http://127.0.0.1:" + gatewayPort + "/health");
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const body = JSON.stringify({kind: "invoice.paid", token: "must-not-leak"});
  const digest = crypto.createHmac("sha256", "e2e-secret")
    .update(timestamp + "." + body)
    .digest("hex");
  const headers = {
    "content-type": "application/json",
    "x-webhook-signature": "sha256=" + digest,
    "x-webhook-timestamp": timestamp,
    "x-webhook-id": "e2e-delivery-1",
    "x-webhook-event": "invoice.paid",
  };
  const accepted = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/hooks/generic",
    {method: "POST", headers, body},
  );
  assert.equal(accepted.status, 202);
  const acceptance = await accepted.json();
  assert.equal(acceptance.accepted, true);
  assert.equal(acceptance.deliveries, 1);

  const duplicate = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/hooks/generic",
    {method: "POST", headers, body},
  );
  assert.equal(duplicate.status, 200);

  const deadline = Date.now() + 12000;
  let delivery;
  while (Date.now() < deadline) {
    const rows = await fetch(
      "http://127.0.0.1:" + gatewayPort + "/api/deliveries",
    ).then(response => response.json());
    delivery = rows[0];
    if (delivery?.state === "delivered") break;
    await sleep(200);
  }
  assert.equal(delivery?.state, "delivered");
  assert.equal(delivery?.attempt, 3);
  assert.equal(attempts, 3);

  const publicEventsText = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/api/events",
  ).then(response => response.text());
  assert.equal(publicEventsText.includes("must-not-leak"), false);
  assert.equal(publicEventsText.includes("[REDACTED]"), true);

  const stats = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/api/stats",
  ).then(response => response.json());
  assert.equal(stats.events, 1);
  assert.equal(stats.delivered, 1);
  assert.equal(fs.existsSync(path.join(dataDir, "state.json")), true);
  console.log("Gateway E2E passed: verified, deduplicated, persisted, retried, delivered, and redacted.");
} finally {
  await stopChild(child);
  await new Promise(resolve => receiver.close(resolve));
  await sleep(200);
  if (path.resolve(dataDir).startsWith(path.resolve(os.tmpdir()))) {
    fs.rmSync(dataDir, {recursive: true, force: true});
  }
}
