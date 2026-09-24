import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import http from 'node:http';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {stopChild} from './e2e-process.mjs';
import pg from 'pg';

const databaseUrl = process.env.TEST_DATABASE_URL;
assert.ok(databaseUrl, 'TEST_DATABASE_URL is required for the PostgreSQL integration test');
assert.match(new URL(databaseUrl).pathname, /^\/hooklab_test(?:_[a-z0-9]+)?$/, 'Use only a dedicated hooklab_test database');
const root = path.resolve(import.meta.dirname, '..');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function unusedPort() {
  const socket = http.createServer();
  await new Promise(resolve => socket.listen(0, '127.0.0.1', resolve));
  const port = socket.address().port;
  await new Promise(resolve => socket.close(resolve));
  return port;
}
async function until(fn, ms = 20000) {
  const end = Date.now() + ms;
  let last;
  while (Date.now() < end) {
    try { const value = await fn(); if (value) return value; } catch (error) { last = error; }
    await delay(100);
  }
  throw last || new Error('Timed out');
}
async function request(base, route, method = 'GET', token = '', body, headers = {}) {
  const response = await fetch(base + route, {method, headers: {
    ...(token ? {authorization: 'Bearer ' + token} : {}),
    ...(body !== undefined ? {'content-type': 'application/json'} : {}), ...headers,
  }, ...(body !== undefined ? {body: typeof body === 'string' ? body : JSON.stringify(body)} : {})});
  const data = await response.json();
  return {status: response.status, data};
}

const portA = await unusedPort(), portB = await unusedPort(), receiverPort = await unusedPort();
const baseA = 'http://127.0.0.1:' + portA, baseB = 'http://127.0.0.1:' + portB;
const receiverBase = 'http://127.0.0.1:' + receiverPort;
const bootstrap = 'bootstrap-test-' + 'a'.repeat(40);
const metricsToken = 'metrics-test-' + 'b'.repeat(40);
const prefix = 'tenant-' + crypto.randomBytes(4).toString('hex');
const deliveries = [];
let retryOnce = true, failPermanent = true, slowGood = false;
const receiver = http.createServer((req, res) => {
  const chunks = [];
  req.on('data', chunk => chunks.push(chunk));
  req.on('end', () => {
    const body = Buffer.concat(chunks).toString('utf8');
    deliveries.push({path: req.url, eventId: req.headers['x-hooklab-event-id'],
      deliveryId: req.headers['x-hooklab-delivery-id'], signature: req.headers['x-hooklab-signature'],
      timestamp: req.headers['x-hooklab-timestamp'], keyId: req.headers['x-hooklab-key-id'],
      eventType: req.headers['x-hooklab-event-type'], traceparent: req.headers.traceparent, body});
    if (req.url === '/bad' && failPermanent) { res.writeHead(400); res.end(); }
    else if (retryOnce) { retryOnce = false; res.writeHead(503, {'retry-after': '0'}); res.end(); }
    else if (slowGood && req.url === '/good') setTimeout(() => { res.writeHead(204); res.end(); }, 1000);
    else { res.writeHead(204); res.end(); }
  });
});
await new Promise(resolve => receiver.listen(receiverPort, '127.0.0.1', resolve));

const children = [];
let logs = '';
function launch(port) {
  const child = spawn(process.platform === 'win32' ? 'moon.exe' : 'moon',
    ['run','--target','js','cmd/hooklab','--','serve-platform',String(port)],
    {cwd: root, detached: process.platform !== 'win32', stdio: ['ignore','pipe','pipe'],
      env: {...process.env, DATABASE_URL: databaseUrl, HOOKLAB_ENCRYPTION_KEY: 'c'.repeat(64),
        HOOKLAB_BOOTSTRAP_TOKEN: bootstrap, HOOKLAB_METRICS_TOKEN: metricsToken,
        HOOKLAB_ALLOW_LOOPBACK_ENDPOINTS: '1', HOOKLAB_ALERT_INTERVAL_MS: '500', HOOKLAB_MAX_WORKERS: '2'}});
  child.stdout.on('data', chunk => { logs += chunk; });
  child.stderr.on('data', chunk => { logs += chunk; });
  children.push(child);
}

try {
  launch(portA); launch(portB);
  await until(async () => (await request(baseA, '/health')).data.status === 'ok' &&
    (await request(baseB, '/health')).data.status === 'ok', 30000);
  const tenantA = prefix + '-a', tenantB = prefix + '-b';
  const createdA = await request(baseA, '/api/admin/tenants', 'POST', bootstrap, {id: tenantA, name: 'Alice'});
  const createdB = await request(baseB, '/api/admin/tenants', 'POST', bootstrap, {id: tenantB, name: 'Bob'});
  assert.equal(createdA.status, 201); assert.equal(createdB.status, 201);
  const ownerA = createdA.data.ownerToken, ownerB = createdB.data.ownerToken;
  const apiA = '/api/tenants/' + tenantA, apiB = '/api/tenants/' + tenantB;
  assert.equal((await request(baseB, apiB + '/catalog', 'GET', ownerA)).status, 401);
  assert.equal((await request(baseB, apiB + '/catalog', 'GET', ownerB)).status, 200);
  const viewer = await request(baseA, apiA + '/keys', 'POST', ownerA, {role: 'viewer', label: 'read only'});
  assert.equal(viewer.status, 201);
  assert.equal((await request(baseA, apiA + '/applications', 'POST', viewer.data.token, {id: 'forbidden'})).status, 403);
  assert.equal((await request(baseA, apiA + '/keys/' + viewer.data.id + '/revoke', 'POST', ownerA)).status, 200);
  assert.equal((await request(baseA, apiA + '/catalog', 'GET', viewer.data.token)).status, 401);

  const application = await request(baseA, apiA + '/applications', 'POST', ownerA, {id: 'orders'});
  assert.equal(application.status, 201);
  const endpoint = await request(baseA, apiA + '/endpoints', 'POST', ownerA, {id: 'consumer', url: receiverBase + '/good'});
  assert.equal(endpoint.status, 201);
  assert.equal((await request(baseA, apiA + '/endpoints', 'POST', ownerA, {id: 'unsafe', url: 'http://169.254.169.254/latest'})).status, 422);
  assert.equal((await request(baseA, apiA + '/subscriptions', 'POST', ownerA,
    {id: 'sub-orders', applicationId: 'orders', endpointId: 'consumer', eventTypes: ['order.created']})).status, 201);
  const contract = await request(baseA, apiA + '/contracts', 'POST', ownerA,
    {applicationId: 'orders', eventType: 'order.created', version: 1, requireCloudEvents: true,
      schema: {type: 'object', required: ['orderId'], properties: {orderId: {type: 'integer'}}}});
  assert.equal(contract.status, 201);
  assert.equal((await request(baseA, apiA + '/contracts', 'POST', ownerA,
    {applicationId: 'orders', eventType: 'order.created', version: 2, requireCloudEvents: true,
      schema: {type: 'object', required: ['orderId','newRequired']}})).status, 409);

  const publishRoute = apiA + '/applications/orders/events/order.created';
  const headers = {'idempotency-key': 'order-1', 'content-type': 'application/cloudevents+json',
    traceparent: '00-' + 'a'.repeat(32) + '-' + 'b'.repeat(16) + '-01'};
  const envelope = {specversion: '1.0', id: 'e-1', source: '/orders', type: 'order.created', data: {orderId: 1}};
  assert.equal((await request(baseA, publishRoute, 'POST', application.data.publishToken,
    {...envelope, data: {wrong: 1}}, headers)).status, 422);
  const published = await request(baseA, publishRoute, 'POST', application.data.publishToken, envelope, headers);
  assert.equal(published.status, 202); assert.equal(published.data.deliveries, 1);
  assert.equal((await request(baseB, publishRoute, 'POST', application.data.publishToken, envelope, headers)).status, 200);
  assert.equal((await request(baseB, publishRoute, 'POST', application.data.publishToken,
    {...envelope, data: {orderId: 2}}, headers)).status, 409);
  await until(async () => {
    const result = await request(baseB, apiA + '/deliveries', 'GET', ownerA);
    return result.data.some(row => row.event_id === published.data.eventId && row.state === 'delivered');
  });
  assert.equal(deliveries.filter(x => x.eventId === published.data.eventId).length, 2);
  for (const received of deliveries.filter(x => x.eventId === published.data.eventId)) {
    const expected = 'v1=' + crypto.createHmac('sha256', endpoint.data.signingSecret)
      .update('v1\n' + received.timestamp + '\n' + received.deliveryId + '\n' + received.eventId + '\n' + received.eventType + '\n' + received.body)
      .digest('hex');
    assert.equal(received.signature, expected);
    assert.match(received.traceparent, /^00-a{32}-[0-9a-f]{16}-01$/);
  }
  const list = await request(baseA, apiA + '/catalog', 'GET', ownerA);
  assert.equal(JSON.stringify(list.data).includes(endpoint.data.signingSecret), false);
  assert.equal(JSON.stringify(list.data).includes(application.data.publishToken), false);
  assert.equal(JSON.stringify(await request(baseA, apiA + '/events', 'GET', ownerA)).includes('orderId'), false);
  const attempts = await request(baseA, apiA + '/deliveries/' +
    (await request(baseA, apiA + '/deliveries', 'GET', ownerA)).data[0].id + '/attempts', 'GET', ownerA);
  assert.equal(attempts.status, 200);
  assert.equal(attempts.data.length, 2);
  const slo = await request(baseA, apiA + '/slo', 'GET', ownerA);
  assert.equal(slo.data.delivered, 1);
  assert.equal((await request(baseA, '/metrics')).status, 401);
  const metricsResponse = await fetch(baseA + '/metrics', {headers: {authorization: 'Bearer ' + metricsToken}});
  assert.equal(metricsResponse.status, 200);
  assert.match(await metricsResponse.text(), /hooklab_deliveries\{state="delivered"\}/);

  slowGood = true;
  const burst = await Promise.all(Array.from({length: 12}, (_, index) => request(baseA, publishRoute, 'POST',
    application.data.publishToken, {...envelope, id: 'burst-' + index, data: {orderId: 100 + index}},
    {...headers, 'idempotency-key': 'burst-' + index})));
  assert.ok(burst.every(item => item.status === 202));
  const pgClient = new pg.Client({connectionString: databaseUrl});
  await pgClient.connect();
  try {
    await until(async () => {
      const active = await pgClient.query("SELECT count(DISTINCT worker_id)::int AS workers FROM deliveries WHERE tenant_id=$1 AND state='in_flight'", [tenantA]);
      return active.rows[0].workers >= 2;
    }, 10000);
  } finally { await pgClient.end(); }
  await until(async () => {
    const rows = (await request(baseA, apiA + '/deliveries', 'GET', ownerA)).data;
    return burst.every(item => rows.some(row => row.event_id === item.data.eventId && row.state === 'delivered'));
  }, 30000);
  assert.ok(burst.every(item => deliveries.filter(row => row.eventId === item.data.eventId).length === 1));
  slowGood = false;

  const badEndpoint = await request(baseA, apiA + '/endpoints', 'POST', ownerA, {id: 'bad-consumer', url: receiverBase + '/bad'});
  assert.equal(badEndpoint.status, 201);
  assert.equal((await request(baseA, apiA + '/subscriptions', 'POST', ownerA,
    {id: 'sub-bad', applicationId: 'orders', endpointId: 'bad-consumer', eventTypes: ['order.created']})).status, 201);
  const second = await request(baseA, publishRoute, 'POST', application.data.publishToken,
    {...envelope, id: 'e-2', data: {orderId: 2}}, {...headers, 'idempotency-key': 'order-2'});
  assert.equal(second.status, 202); assert.equal(second.data.deliveries, 2);
  const dead = await until(async () => {
    const rows = (await request(baseB, apiA + '/deliveries', 'GET', ownerA)).data;
    return rows.find(row => row.event_id === second.data.eventId && row.endpoint_id === 'bad-consumer' && row.state === 'dead_lettered');
  });
  await until(async () => (await request(baseA, apiA + '/alerts', 'GET', ownerA)).data.some(row => row.kind === 'dead_letters' && row.state === 'open'));
  failPermanent = false;
  assert.equal((await request(baseA, apiA + '/deliveries/' + dead.id + '/retry', 'POST', ownerA)).status, 202);
  await until(async () => (await request(baseA, apiA + '/deliveries', 'GET', ownerA)).data.some(row => row.id === dead.id && row.state === 'delivered'));

  const rotated = await request(baseA, apiA + '/endpoints/consumer/rotate-secret', 'POST', ownerA);
  assert.equal(rotated.status, 200);
  assert.notEqual(rotated.data.signingSecret, endpoint.data.signingSecret);
  const rotatedPublisher = await request(baseA, apiA + '/applications/orders/rotate-token', 'POST', ownerA);
  assert.equal(rotatedPublisher.status, 200);
  assert.equal((await request(baseA, publishRoute, 'POST', application.data.publishToken,
    {...envelope, id: 'old-token'}, {...headers, 'idempotency-key': 'old-token'})).status, 401);
  const portal = await fetch(baseA + '/');
  assert.equal(portal.status, 200); assert.match(await portal.text(), /消费者门户/);
  assert.ok((await request(baseA, apiA + '/audit', 'GET', ownerA)).data.length >= 7);
  console.log('Platform E2E passed: two workers, tenant isolation, RBAC, contracts, CloudEvents, signed retry, dead-letter recovery, SLO and alerts.');
} catch (error) {
  console.error(logs);
  throw error;
} finally {
  for (const child of children) await stopChild(child);
  await new Promise(resolve => receiver.close(resolve));
}
