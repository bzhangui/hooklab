import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import http from 'node:http';
import path from 'node:path';
import {spawn, execFileSync} from 'node:child_process';
import pg from 'pg';
import {stopChild} from './e2e-process.mjs';

// A repeatable, synthetic evaluation scenario. Never point this at a shared DB.
const databaseUrl = process.env.TEST_DATABASE_URL;
assert.ok(databaseUrl, 'TEST_DATABASE_URL is required');
assert.match(new URL(databaseUrl).pathname, /^\/hooklab_test(?:_[a-z0-9]+)?$/,
  'Use only a dedicated hooklab_test database');
const root = path.resolve(import.meta.dirname, '..');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const bootstrap = 'showcase-bootstrap-' + 'a'.repeat(40);
const metricsToken = 'showcase-metrics-' + 'b'.repeat(40);
const tenant = 'showcase-' + crypto.randomBytes(5).toString('hex');
const events = [];
const children = [];
let holdFirst = true;
let logs = '';

async function freePort() {
  const server = http.createServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port;
}
async function until(check, timeoutMs = 30000) {
  const deadline = Date.now() + timeoutMs;
  let last;
  while (Date.now() < deadline) {
    try { const result = await check(); if (result) return result; }
    catch (error) { last = error; }
    await pause(100);
  }
  throw last || new Error('Timed out waiting for showcase state');
}
async function api(base, route, method = 'GET', token = '', body, headers = {}) {
  const response = await fetch(base + route, {method, headers: {
    ...(token ? {authorization: 'Bearer ' + token} : {}),
    ...(body === undefined ? {} : {'content-type': 'application/json'}), ...headers,
  }, ...(body === undefined ? {} : {body: JSON.stringify(body)})});
  return {status: response.status, data: await response.json()};
}
function percentile(values, fraction) {
  const sorted = [...values].sort((a, b) => a - b);
  return Math.round(sorted[Math.ceil(sorted.length * fraction) - 1]);
}
function launch(port) {
  const child = spawn(process.platform === 'win32' ? 'moon.exe' : 'moon',
    ['run', '--target', 'js', 'cmd/hooklab', '--', 'serve-platform', String(port)],
    {cwd: root, detached: process.platform !== 'win32', stdio: ['ignore', 'pipe', 'pipe'],
      env: {...process.env, DATABASE_URL: databaseUrl, HOOKLAB_ENCRYPTION_KEY: 'c'.repeat(64),
        HOOKLAB_BOOTSTRAP_TOKEN: bootstrap, HOOKLAB_METRICS_TOKEN: metricsToken,
        HOOKLAB_ALLOW_LOOPBACK_ENDPOINTS: '1', HOOKLAB_MAX_WORKERS: '4'}});
  child.stdout.on('data', chunk => { logs += chunk; });
  child.stderr.on('data', chunk => { logs += chunk; });
  children.push(child);
  return child;
}
async function crash(child) {
  // Kill the entire spawned process tree: graceful shutdown would wait for the
  // HTTP attempt and would not exercise lease-expiry takeover.
  if (process.platform === 'win32') {
    execFileSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], {stdio: 'ignore'});
  } else {
    process.kill(-child.pid, 'SIGKILL');
  }
  await until(() => child.exitCode !== null || child.signalCode !== null, 5000);
}

const portA = await freePort();
const portB = await freePort();
const receiverPort = await freePort();
const baseA = 'http://127.0.0.1:' + portA;
const baseB = 'http://127.0.0.1:' + portB;
const receiver = http.createServer((req, res) => {
  req.resume();
  req.on('end', () => {
    events.push({eventId: req.headers['x-hooklab-event-id'],
      deliveryId: req.headers['x-hooklab-delivery-id']});
    if (holdFirst) { holdFirst = false; return; } // Simulate a lost response.
    res.writeHead(204);
    res.end();
  });
});
await new Promise(resolve => receiver.listen(receiverPort, '127.0.0.1', resolve));
const client = new pg.Client({connectionString: databaseUrl});

try {
  await client.connect();
  const first = launch(portA);
  await until(async () => (await api(baseA, '/health')).data.status === 'ok', 30000);
  const created = await api(baseA, '/api/admin/tenants', 'POST', bootstrap, {id: tenant, name: 'Synthetic order demo'});
  assert.equal(created.status, 201);
  const owner = created.data.ownerToken;
  const route = '/api/tenants/' + tenant;
  const application = await api(baseA, route + '/applications', 'POST', owner, {id: 'orders'});
  assert.equal(application.status, 201);
  const endpoint = await api(baseA, route + '/endpoints', 'POST', owner,
    {id: 'warehouse', url: 'http://127.0.0.1:' + receiverPort + '/orders'});
  assert.equal(endpoint.status, 201);
  assert.equal((await api(baseA, route + '/subscriptions', 'POST', owner,
    {id: 'orders-to-warehouse', applicationId: 'orders', endpointId: 'warehouse', eventTypes: ['order.created']})).status, 201);
  assert.equal((await api(baseA, route + '/contracts', 'POST', owner,
    {applicationId: 'orders', eventType: 'order.created', version: 1, requireCloudEvents: true,
      schema: {type: 'object', required: ['orderId'], properties: {orderId: {type: 'integer'}}}})).status, 201);
  const publishRoute = route + '/applications/orders/events/order.created';
  const publish = (base, token, key, orderId) => api(base, publishRoute, 'POST', token,
    {specversion: '1.0', id: key, source: '/orders', type: 'order.created', data: {orderId}},
    {'content-type': 'application/cloudevents+json', 'idempotency-key': key});

  const rejected = await publish(baseA, application.data.publishToken, 'invalid-order', 'not-an-integer');
  assert.equal(rejected.status, 422);
  assert.equal((await client.query('SELECT count(*)::int AS n FROM events WHERE tenant_id=$1', [tenant])).rows[0].n, 0);
  const accepted = await publish(baseA, application.data.publishToken, 'failover-order', 42);
  assert.equal(accepted.status, 202);
  await until(() => events.some(item => item.eventId === accepted.data.eventId));
  const claimed = await until(async () => {
    const result = await client.query('SELECT id,state,attempt,worker_id FROM deliveries WHERE event_id=$1', [accepted.data.eventId]);
    return result.rows[0]?.state === 'in_flight' ? result.rows[0] : null;
  });
  assert.equal(claimed.attempt, 1);
  const crashAt = performance.now();
  await crash(first);
  launch(portB);
  await until(async () => (await api(baseB, '/health')).data.status === 'ok', 30000);
  const recovered = await until(async () => {
    const result = await client.query('SELECT id,state,attempt FROM deliveries WHERE event_id=$1', [accepted.data.eventId]);
    return result.rows[0]?.state === 'delivered' ? result.rows[0] : null;
  }, 45000);
  const recoveryMs = Math.round(performance.now() - crashAt);
  assert.equal(recovered.id, claimed.id);
  assert.equal(recovered.attempt, 2);
  assert.equal(events.filter(item => item.eventId === accepted.data.eventId).length, 2);
  assert.equal(new Set(events.filter(item => item.eventId === accepted.data.eventId).map(item => item.deliveryId)).size, 1);
  assert.equal((await client.query('SELECT count(*)::int AS n FROM delivery_attempts WHERE delivery_id=$1', [recovered.id])).rows[0].n, 1);

  // The following timings describe only this disposable loopback setup. They
  // are not production throughput or an external-user deployment claim.
  const sampleSize = 32;
  const publishLatencies = [];
  const batchStart = performance.now();
  const published = await Promise.all(Array.from({length: sampleSize}, async (_, index) => {
    const start = performance.now();
    const result = await publish(baseB, application.data.publishToken, 'sample-' + index, index + 100);
    publishLatencies.push(performance.now() - start);
    assert.equal(result.status, 202);
    return result.data.eventId;
  }));
  const acceptedMs = Math.round(performance.now() - batchStart);
  await until(async () => {
    const result = await client.query("SELECT count(*)::int AS n FROM deliveries WHERE event_id=ANY($1::uuid[]) AND state='delivered'", [published]);
    return result.rows[0].n === sampleSize;
  }, 30000);
  const deliveredMs = Math.round(performance.now() - batchStart);
  assert.equal((await api(baseB, route + '/catalog', 'GET', 'wrong-token')).status, 401);
  const summary = {
    scenario: 'synthetic_loopback_order_delivery',
    contract_rejection_without_persistence: true,
    failover: {same_delivery_id: true, network_attempts: 2, persisted_successful_attempts: 1,
      lease_takeover_ms: recoveryMs, final_state: recovered.state},
    local_sample: {events: sampleSize, concurrent_publish_calls: sampleSize,
      publish_batch_ms: acceptedMs, publish_p50_ms: percentile(publishLatencies, 0.5),
      publish_p95_ms: percentile(publishLatencies, 0.95), all_delivered_ms: deliveredMs},
    limitations: 'Synthetic loopback only; no real user, external network, high availability, or production SLO claim.',
  };
  console.log(JSON.stringify(summary, null, 2));
} catch (error) {
  console.error(logs);
  throw error;
} finally {
  await client.end().catch(() => {});
  for (const child of children) await stopChild(child);
  await new Promise(resolve => receiver.close(resolve));
}
