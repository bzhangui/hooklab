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
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "hooklab-outbound-"));
const dataDir = path.join(tempDir, "state");
const configPath = path.join(tempDir, "gateway.json");
const target = "http://127.0.0.1:" + receiverPort + "/events";
const publishToken = "publisher-test-token";
const billingPublishToken = "billing-publisher-test-token";
const signingSecret = "endpoint-signing-secret";
const attempts = [];

const receiver = http.createServer((req, res) => {
  const chunks = [];
  req.on("data", chunk => chunks.push(chunk));
  req.on("end", () => {
    const body = Buffer.concat(chunks).toString("utf8");
    const timestamp = req.headers["x-hooklab-timestamp"];
    const deliveryId = req.headers["x-hooklab-delivery-id"];
    const eventId = req.headers["x-hooklab-event-id"];
    const eventType = req.headers["x-hooklab-event-type"];
    const expected = "v1=" + crypto.createHmac("sha256", signingSecret)
      .update("v1\n" + timestamp + "\n" + deliveryId + "\n" + eventId + "\n" + eventType + "\n" + body)
      .digest("hex");
    attempts.push({
      body,
      timestamp,
      deliveryId,
      eventId,
      eventType,
      keyId: req.headers["x-hooklab-key-id"],
      signature: req.headers["x-hooklab-signature"],
      expected,
    });
    if (attempts.length === 1) {
      res.writeHead(503, {"retry-after": "0"});
      res.end("retry");
    } else {
      res.writeHead(204);
      res.end();
    }
  });
});
await new Promise(resolve => receiver.listen(receiverPort, "127.0.0.1", resolve));

fs.writeFileSync(configPath, JSON.stringify({
  version: 1,
  provider: "generic-hmac",
  secret_env: "HOOKLAB_INGRESS_SECRET",
  previous_secrets_env: null,
  port: gatewayPort,
  data_dir: dataDir,
  routes: [{name: "all", path: "$", operator: "exists", target}],
  outbound: {
    applications: [
      {
        id: "orders",
        publish_token_env: "HOOKLAB_PUBLISH_ORDERS",
      },
      {
        id: "billing",
        publish_token_env: "HOOKLAB_PUBLISH_BILLING",
      },
    ],
    endpoints: [{
      id: "warehouse",
      url: target,
      signing_secret_env: "HOOKLAB_SIGN_WAREHOUSE",
      key_id: "warehouse-v1",
    }],
    subscriptions: [
      {
        id: "orders-created",
        application: "orders",
        endpoint: "warehouse",
        event_types: ["order.created"],
      },
      {
        id: "billing-order-created",
        application: "billing",
        endpoint: "warehouse",
        event_types: ["order.created"],
      },
    ],
  },
}), "utf8");

const child = spawn(
  process.platform === "win32" ? "moon.exe" : "moon",
  ["run", "--target", "js", "cmd/hooklab", "--", "serve-config", configPath],
  {
    cwd: root,
    stdio: ["ignore", "pipe", "pipe"],
    env: {
      ...process.env,
      HOOKLAB_INGRESS_SECRET: "unused-ingress-secret",
      HOOKLAB_PUBLISH_ORDERS: publishToken,
      HOOKLAB_PUBLISH_BILLING: billingPublishToken,
      HOOKLAB_SIGN_WAREHOUSE: signingSecret,
    },
    detached: process.platform !== "win32",
  },
);
let logs = "";
child.stdout.on("data", chunk => { logs += chunk; });
child.stderr.on("data", chunk => { logs += chunk; });

try {
  const health = await waitFor(
    "http://127.0.0.1:" + gatewayPort + "/health",
    value => value.status === "ok",
  );
  assert.equal(health.storage, "sqlite");

  const malformedPath = await fetch(
    "http://127.0.0.1:" + gatewayPort +
      "/api/outbound/applications/%/events/order.created",
    {
      method: "POST",
      headers: {
        "authorization": "Bearer " + publishToken,
        "content-type": "application/json",
        "idempotency-key": "malformed-path",
      },
      body: "{}",
    },
  );
  assert.equal(malformedPath.status, 400, logs);
  const healthAfterMalformedPath = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/health",
  );
  assert.equal(healthAfterMalformedPath.status, 200, logs);
  assert.equal((await healthAfterMalformedPath.json()).status, "ok");

  const publishUrl = "http://127.0.0.1:" + gatewayPort +
    "/api/outbound/applications/orders/events/order.created";
  const rejected = await fetch(publishUrl, {
    method: "POST",
    headers: {
      "authorization": "Bearer wrong-token",
      "content-type": "application/json",
      "idempotency-key": "order-42",
    },
    body: "{}",
  });
  assert.equal(rejected.status, 401);

  const invalid = await fetch(publishUrl, {
    method: "POST",
    headers: {
      "authorization": "Bearer " + publishToken,
      "content-type": "application/json",
      "idempotency-key": "invalid-json",
    },
    body: "{",
  });
  assert.equal(invalid.status, 422);

  const invalidMediaType = await fetch(publishUrl, {
    method: "POST",
    headers: {
      "authorization": "Bearer " + publishToken,
      "content-type": "application/jsonp",
      "idempotency-key": "invalid-media-type",
    },
    body: "{}",
  });
  assert.equal(invalidMediaType.status, 415);

  const payload = JSON.stringify({order_id: "order-42", token: "must-not-leak"});
  const accepted = await fetch(publishUrl, {
    method: "POST",
    headers: {
      "authorization": "Bearer " + publishToken,
      "content-type": "application/json",
      "idempotency-key": "order-42",
    },
    body: payload,
  });
  assert.equal(accepted.status, 202, logs);
  const acceptance = await accepted.json();
  assert.equal(acceptance.accepted, true);
  assert.equal(acceptance.deliveries, 1);

  const deliveries = await waitFor(
    "http://127.0.0.1:" + gatewayPort + "/api/deliveries",
    value => value.length === 1 && value[0].state === "delivered",
  );
  assert.equal(deliveries[0].attempt, 2);
  assert.equal(deliveries[0].endpointId, "warehouse");
  assert.equal(deliveries[0].subscriptionId, "orders-created");
  assert.equal(attempts.length, 2);
  assert.equal(attempts[0].body, payload);
  assert.equal(attempts[1].body, payload);
  assert.equal(attempts[0].deliveryId, attempts[1].deliveryId);
  assert.equal(attempts[0].eventId, attempts[1].eventId);
  assert.equal(attempts[0].eventType, "order.created");
  assert.equal(attempts[0].keyId, "warehouse-v1");
  assert.equal(attempts[0].signature, attempts[0].expected);
  assert.equal(attempts[1].signature, attempts[1].expected);

  const duplicate = await fetch(publishUrl, {
    method: "POST",
    headers: {
      "authorization": "Bearer " + publishToken,
      "content-type": "application/json",
      "idempotency-key": "order-42",
    },
    body: payload,
  });
  assert.equal(duplicate.status, 200);
  assert.equal((await duplicate.json()).duplicate, true);

  const billingPublishUrl = "http://127.0.0.1:" + gatewayPort +
    "/api/outbound/applications/billing/events/order.created";
  const billingPayload = JSON.stringify({invoice_id: "invoice-42"});
  const billingAccepted = await fetch(billingPublishUrl, {
    method: "POST",
    headers: {
      "authorization": "Bearer " + billingPublishToken,
      "content-type": "application/json",
      // Idempotency keys are scoped to an application, not globally.
      "idempotency-key": "order-42",
    },
    body: billingPayload,
  });
  assert.equal(billingAccepted.status, 202, logs);
  const billingAcceptance = await billingAccepted.json();
  assert.equal(billingAcceptance.accepted, true);
  assert.equal(billingAcceptance.deliveries, 1);
  const deliveriesAfterBilling = await waitFor(
    "http://127.0.0.1:" + gatewayPort + "/api/deliveries",
    value => value.length === 2 && value.every(item => item.state === "delivered"),
  );
  const billingDelivery = deliveriesAfterBilling.find(
    item => item.subscriptionId === "billing-order-created",
  );
  assert.ok(billingDelivery);
  assert.equal(billingDelivery.attempt, 1);
  assert.equal(attempts.length, 3);
  assert.equal(attempts[2].body, billingPayload);
  assert.notEqual(attempts[2].eventId, attempts[0].eventId);

  const conflict = await fetch(publishUrl, {
    method: "POST",
    headers: {
      "authorization": "Bearer " + publishToken,
      "content-type": "application/json",
      "idempotency-key": "order-42",
    },
    body: JSON.stringify({order_id: "different"}),
  });
  assert.equal(conflict.status, 409);

  await sleep(300);
  assert.equal(attempts.length, 3);
  const eventsText = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/api/events",
  ).then(response => response.text());
  assert.equal(eventsText.includes("must-not-leak"), false);
  assert.equal(eventsText.includes(publishToken), false);
  assert.equal(eventsText.includes(billingPublishToken), false);
  assert.equal(eventsText.includes(signingSecret), false);

  const catalogText = await fetch(
    "http://127.0.0.1:" + gatewayPort + "/api/outbound/catalog",
  ).then(response => response.text());
  assert.equal(catalogText.includes("HOOKLAB_PUBLISH_ORDERS"), false);
  assert.equal(catalogText.includes("HOOKLAB_PUBLISH_BILLING"), false);
  assert.equal(catalogText.includes("HOOKLAB_SIGN_WAREHOUSE"), false);
  assert.equal(catalogText.includes(publishToken), false);
  assert.equal(catalogText.includes(billingPublishToken), false);
  assert.equal(catalogText.includes(signingSecret), false);

  const concurrentPayload = JSON.stringify({order_id: "order-concurrent"});
  const concurrent = await Promise.all(Array.from({length: 16}, () =>
    fetch(publishUrl, {
      method: "POST",
      headers: {
        "authorization": "Bearer " + publishToken,
        "content-type": "application/json",
        "idempotency-key": "order-concurrent",
      },
      body: concurrentPayload,
    })
  ));
  const statuses = concurrent.map(response => response.status);
  assert.equal(statuses.filter(status => status === 202).length, 1);
  assert.equal(statuses.filter(status => status === 200).length, 15);
  await waitFor(
    "http://127.0.0.1:" + gatewayPort + "/api/deliveries",
    value => value.length === 3 && value.every(item => item.state === "delivered"),
  );
  assert.equal(attempts.length, 4);
  assert.equal(fs.existsSync(path.join(dataDir, "hooklab.sqlite")), true);
  console.log("Gateway outbound E2E passed: authenticated publish, application-scoped idempotency, malformed-path recovery, signed retry, redaction, and SQLite persistence.");
} finally {
  await stopChild(child);
  await new Promise(resolve => receiver.close(resolve));
  await sleep(200);
  if (path.resolve(tempDir).startsWith(path.resolve(os.tmpdir()))) {
    fs.rmSync(tempDir, {recursive: true, force: true});
  }
}
