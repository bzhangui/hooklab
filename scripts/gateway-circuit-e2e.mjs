import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import {spawn, spawnSync} from "node:child_process";
import {stopChild} from "./e2e-process.mjs";

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function unusedPort() {
  const server = http.createServer();
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port;
}

async function waitFor(url, predicate, timeoutMs = 12000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
      if (response.ok) {
        const value = await response.json();
        if (predicate(value)) return value;
      }
    } catch (_) {}
    await sleep(50);
  }
  throw new Error("Timed out waiting for " + url);
}

const root = path.resolve(import.meta.dirname, "..");
const gatewayPort = await unusedPort();
const flakyPort = await unusedPort();
const fastPort = await unusedPort();
const permanentPort = await unusedPort();
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "hooklab-circuit-"));
const configPath = path.join(dataDir, "gateway.json");
const flakyTarget = `http://127.0.0.1:${flakyPort}/flaky`;
const fastTarget = `http://127.0.0.1:${fastPort}/fast`;
const permanentTarget = `http://127.0.0.1:${permanentPort}/permanent`;
const route = (name, kind, target) => ({
  name, path: "kind", operator: "equals", expected: kind, target,
});
fs.writeFileSync(configPath, JSON.stringify({
  version: 1,
  provider: "generic-hmac",
  secret_env: "HOOKLAB_CIRCUIT_SECRET",
  previous_secrets_env: null,
  port: gatewayPort,
  data_dir: path.join(dataDir, "state"),
  routes: [
    route("flaky", "temporary", flakyTarget),
    route("fast", "temporary", fastTarget),
    route("permanent", "permanent", permanentTarget),
  ],
  delivery_limits: [{target: flakyTarget, max_concurrency: 2}],
  circuit_breakers: [
    {target: flakyTarget, failure_threshold: 1, open_ms: 1500},
    {target: permanentTarget, failure_threshold: 1, open_ms: 1500},
  ],
}), "utf8");

const moon = process.platform === "win32" ? "moon.exe" : "moon";
const checked = spawnSync(moon, [
  "run", "--target", "js", "cmd/hooklab", "--", "config-check", configPath,
], {cwd: root, encoding: "utf8"});
assert.equal(checked.status, 0, checked.stderr);
assert.equal(JSON.parse(checked.stdout.trim().split(/\r?\n/).at(-1)).circuit_breakers, 2);

const flakyStarts = [];
const flakyEnds = [];
let fastReceived = 0;
let permanentReceived = 0;
const flakyReceiver = http.createServer((req, res) => {
  req.resume();
  const attempt = flakyStarts.length + 1;
  flakyStarts.push(Date.now());
  setTimeout(() => {
    flakyEnds.push(Date.now());
    res.writeHead(attempt === 1 ? 503 : 204);
    res.end();
  }, attempt === 2 ? 450 : 0);
});
const fastReceiver = http.createServer((req, res) => {
  req.resume();
  fastReceived++;
  res.writeHead(204);
  res.end();
});
const permanentReceiver = http.createServer((req, res) => {
  req.resume();
  permanentReceived++;
  res.writeHead(400);
  res.end();
});
await new Promise(resolve => flakyReceiver.listen(flakyPort, "127.0.0.1", resolve));
await new Promise(resolve => fastReceiver.listen(fastPort, "127.0.0.1", resolve));
await new Promise(resolve => permanentReceiver.listen(permanentPort, "127.0.0.1", resolve));

const child = spawn(moon, [
  "run", "--target", "js", "cmd/hooklab", "--", "serve-config", configPath,
], {
  cwd: root,
  stdio: "ignore",
  env: {...process.env, HOOKLAB_CIRCUIT_SECRET: "circuit-secret"},
  detached: process.platform !== "win32",
});

try {
  const base = `http://127.0.0.1:${gatewayPort}`;
  await waitFor(base + "/health", value => value.status === "ok");
  const dashboard = await fetch(base + "/").then(response => response.text());
  assert.ok(dashboard.includes("投递耗时") && dashboard.includes("熔断"));
  const send = async (kind, id) => {
    const body = JSON.stringify({kind, marker: "private-circuit-test-token"});
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const signature = crypto.createHmac("sha256", "circuit-secret")
      .update(timestamp + "." + body).digest("hex");
    const response = await fetch(base + "/hooks/generic-hmac", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-webhook-signature": "sha256=" + signature,
        "x-webhook-timestamp": timestamp,
        "x-webhook-id": id,
        "x-webhook-event": kind,
      },
      body,
    });
    assert.equal(response.status, 202);
    return response.json();
  };
  const first = await send("temporary", "circuit-temporary-1");
  await waitFor(base + "/api/deliveries", rows =>
    rows.some(item => item.target === flakyTarget &&
      item.state === "scheduled" && item.attempt === 1 &&
      item.circuitState === "open"),
  );
  const replay = await fetch(base + "/api/events/" +
    encodeURIComponent(first.eventId) + "/replay", {method: "POST"});
  assert.equal(replay.status, 202);
  assert.equal((await replay.json()).replayed, 2);
  const waiting = await waitFor(base + "/api/deliveries", rows =>
    rows.filter(item => item.target === flakyTarget).length === 2 &&
    rows.filter(item => item.target === fastTarget && item.state === "delivered").length === 2,
  );
  assert.equal(waiting.filter(item => item.target === flakyTarget &&
    item.state === "pending" && item.attempt === 0).length, 1,
  "an open circuit must not consume a replay attempt");
  assert.equal(fastReceived, 2, "another target must continue delivering");

  await waitFor(base + "/api/deliveries", rows =>
    rows.filter(item => item.target === flakyTarget && item.state === "delivered").length === 2,
  );
  assert.equal(flakyStarts.length, 3);
  assert.ok(flakyStarts[2] >= flakyEnds[1],
    "only one half-open probe may run, even with two concurrency slots");

  await send("permanent", "circuit-permanent-1");
  await waitFor(base + "/api/deliveries", rows =>
    rows.filter(item => item.target === permanentTarget && item.state === "dead_lettered").length === 1,
  );
  await send("permanent", "circuit-permanent-2");
  const finalRows = await waitFor(base + "/api/deliveries", rows =>
    rows.filter(item => item.target === permanentTarget && item.state === "dead_lettered").length === 2,
  );
  assert.equal(permanentReceived, 2);
  assert.ok(finalRows.filter(item => item.target === permanentTarget)
    .every(item => item.circuitState === "closed" && item.attempt === 1),
  "permanent HTTP 400 must not trip the breaker");

  const metricsResponse = await fetch(base + "/api/metrics");
  assert.equal(metricsResponse.status, 200);
  const metricsText = await metricsResponse.text();
  const metrics = JSON.parse(metricsText);
  assert.equal(metrics.total, 7);
  assert.equal(metrics.targets.length, 3);
  assert.ok(metrics.targets.every(item => /^target-[1-3]$/.test(item.id)));
  assert.ok(!metricsText.includes("127.0.0.1") &&
    !metricsText.includes("private-circuit-test-token"));
  console.log("Gateway circuit, half-open probe, replay, permanent 4xx, and latency E2E passed.");
} finally {
  await stopChild(child);
  await Promise.all([flakyReceiver, fastReceiver, permanentReceiver].map(
    server => new Promise(resolve => server.close(resolve)),
  ));
  if (path.resolve(dataDir).startsWith(path.resolve(os.tmpdir()))) {
    fs.rmSync(dataDir, {recursive: true, force: true});
  }
}
