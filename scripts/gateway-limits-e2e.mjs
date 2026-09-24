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
const slowPort = await unusedPort();
const fastPort = await unusedPort();
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "hooklab-limits-"));
const configPath = path.join(dataDir, "gateway.json");
const slowTarget = `http://127.0.0.1:${slowPort}/slow`;
const fastTarget = `http://127.0.0.1:${fastPort}/fast`;
const route = (name, target) => ({
  name, path: "kind", operator: "equals", expected: "invoice.paid", target,
});
fs.writeFileSync(configPath, JSON.stringify({
  version: 1,
  provider: "generic-hmac",
  secret_env: "HOOKLAB_LIMIT_SECRET",
  previous_secrets_env: null,
  port: gatewayPort,
  data_dir: path.join(dataDir, "state"),
  routes: [route("slow", slowTarget), route("fast", fastTarget)],
  delivery_limits: [{
    target: slowTarget, max_concurrency: 2, requests_per_second: 2,
  }],
}), "utf8");

const moon = process.platform === "win32" ? "moon.exe" : "moon";
const checked = spawnSync(moon, [
  "run", "--target", "js", "cmd/hooklab", "--", "config-check", configPath,
], {cwd: root, encoding: "utf8"});
assert.equal(checked.status, 0, checked.stderr);
assert.equal(JSON.parse(checked.stdout.trim().split(/\r?\n/).at(-1)).delivery_limits, 1);

let activeSlow = 0;
let maxActiveSlow = 0;
const slowStarts = [];
const slowEnds = [];
const fastStarts = [];
const slowReceiver = http.createServer((req, res) => {
  req.resume();
  activeSlow++;
  maxActiveSlow = Math.max(maxActiveSlow, activeSlow);
  slowStarts.push(performance.now());
  setTimeout(() => {
    slowEnds.push(performance.now());
    activeSlow--;
    res.writeHead(204);
    res.end();
  }, 450);
});
const fastReceiver = http.createServer((req, res) => {
  req.resume();
  fastStarts.push(performance.now());
  res.writeHead(204);
  res.end();
});
await new Promise(resolve => slowReceiver.listen(slowPort, "127.0.0.1", resolve));
await new Promise(resolve => fastReceiver.listen(fastPort, "127.0.0.1", resolve));

const child = spawn(moon, [
  "run", "--target", "js", "cmd/hooklab", "--", "serve-config", configPath,
], {
  cwd: root,
  stdio: "ignore",
  env: {...process.env, HOOKLAB_LIMIT_SECRET: "limit-secret"},
  detached: process.platform !== "win32",
});

try {
  const base = `http://127.0.0.1:${gatewayPort}`;
  await waitFor(base + "/health", value => value.status === "ok");
  const send = async index => {
    const body = JSON.stringify({kind: "invoice.paid", index});
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const signature = crypto.createHmac("sha256", "limit-secret")
      .update(timestamp + "." + body).digest("hex");
    const response = await fetch(base + "/hooks/generic-hmac", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-webhook-signature": "sha256=" + signature,
        "x-webhook-timestamp": timestamp,
        "x-webhook-id": `limit-event-${index}`,
        "x-webhook-event": "invoice.paid",
      },
      body,
    });
    assert.equal(response.status, 202);
    assert.equal((await response.json()).deliveries, 2);
  };
  await Promise.all([send(1), send(2), send(3)]);
  await waitFor(base + "/api/deliveries", value =>
    value.length === 6 && value.every(item => item.state === "delivered"),
  );
  assert.equal(slowStarts.length, 3);
  assert.equal(fastStarts.length, 3);
  assert.equal(maxActiveSlow, 2, "slow target should use both configured slots");
  // Network arrival trails limiter admission and varies under CI scheduling.
  // The exact one-second boundary is asserted by the MoonBit limiter tests;
  // here we check that the third request is materially delayed end to end.
  const slowGapMs = slowStarts[2] - slowStarts[0];
  assert.ok(slowGapMs >= 750,
    `third slow attempt should be rate-delayed (observed ${Math.round(slowGapMs)}ms)`);
  assert.ok(fastStarts[0] < slowEnds[0],
    "fast target should not wait for the slow target to finish");
  console.log("Gateway target concurrency, rate, and isolation E2E passed.");
} finally {
  await stopChild(child);
  await new Promise(resolve => slowReceiver.close(resolve));
  await new Promise(resolve => fastReceiver.close(resolve));
  if (path.resolve(dataDir).startsWith(path.resolve(os.tmpdir()))) {
    fs.rmSync(dataDir, {recursive: true, force: true});
  }
}
