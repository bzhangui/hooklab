import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import http from 'node:http';
import path from 'node:path';
import {spawn} from 'node:child_process';
import pg from 'pg';
import {stopChild} from './e2e-process.mjs';

const databaseUrl = process.env.TEST_DATABASE_URL;
assert.ok(databaseUrl, 'TEST_DATABASE_URL is required');
assert.match(new URL(databaseUrl).pathname, /^\/hooklab_test(?:_[a-z0-9]+)?$/,
  'Use only a dedicated hooklab_test database');
const root = path.resolve(import.meta.dirname, '..');
const tenant = 'quota-' + crypto.randomBytes(5).toString('hex');
const otherTenant = tenant + '-other';
const bootstrap = 'quota-bootstrap-' + 'a'.repeat(40);
const metrics = 'quota-metrics-' + 'b'.repeat(40);
const children = [];
let logs = '';

async function freePort() {
  const socket = http.createServer();
  await new Promise(resolve => socket.listen(0, '127.0.0.1', resolve));
  const port = socket.address().port;
  await new Promise(resolve => socket.close(resolve));
  return port;
}
async function until(check, timeoutMs = 30000) {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    try { if (await check()) return; } catch (_) {}
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error('Timed out waiting for quota test servers');
}
async function api(base, route, method = 'GET', token = '', body, headers = {}) {
  const response = await fetch(base + route, {method, headers: {
    ...(token ? {authorization: 'Bearer ' + token} : {}),
    ...(body !== undefined ? {'content-type': 'application/json'} : {}), ...headers,
  }, ...(body !== undefined ? {body: JSON.stringify(body)} : {})});
  return {status: response.status, data: await response.json()};
}
function launch(port) {
  const child = spawn(process.platform === 'win32' ? 'moon.exe' : 'moon',
    ['run', '--target', 'js', 'cmd/hooklab', '--', 'serve-platform', String(port)],
    {cwd: root, detached: process.platform !== 'win32', stdio: ['ignore', 'pipe', 'pipe'],
      env: {...process.env, DATABASE_URL: databaseUrl, HOOKLAB_ENCRYPTION_KEY: 'd'.repeat(64),
        HOOKLAB_BOOTSTRAP_TOKEN: bootstrap, HOOKLAB_METRICS_TOKEN: metrics,
        HOOKLAB_TENANT_HOURLY_EVENT_LIMIT: '2'}});
  child.stdout.on('data', chunk => { logs += chunk; });
  child.stderr.on('data', chunk => { logs += chunk; });
  children.push(child);
}

const portA = await freePort(), portB = await freePort();
const baseA = 'http://127.0.0.1:' + portA, baseB = 'http://127.0.0.1:' + portB;
const client = new pg.Client({connectionString: databaseUrl});
try {
  launch(portA); launch(portB);
  await until(async () => (await api(baseA, '/health')).status === 200 && (await api(baseB, '/health')).status === 200);
  await client.connect();
  const created = await api(baseA, '/api/admin/tenants', 'POST', bootstrap, {id: tenant, name: 'Quota synthetic tenant'});
  assert.equal(created.status, 201);
  const application = await api(baseA, '/api/tenants/' + tenant + '/applications', 'POST', created.data.ownerToken, {id: 'orders'});
  assert.equal(application.status, 201);
  const route = '/api/tenants/' + tenant + '/applications/orders/events/order.created';
  const publish = (base, index) => api(base, route, 'POST', application.data.publishToken,
    {orderId: index}, {'idempotency-key': 'quota-' + index});
  const results = await Promise.all(Array.from({length: 8}, (_, index) => publish(index % 2 ? baseA : baseB, index)));
  assert.equal(results.filter(row => row.status === 202).length, 2);
  assert.equal(results.filter(row => row.status === 429 && row.data.error === 'quota_exceeded').length, 6);
  const accepted = results.findIndex(row => row.status === 202);
  const duplicate = await publish(baseB, accepted);
  assert.equal(duplicate.status, 200);
  assert.equal(duplicate.data.eventId, results[accepted].data.eventId);
  assert.equal((await api(baseA, route, 'POST', application.data.publishToken,
    {orderId: 999}, {'idempotency-key': 'quota-' + accepted})).status, 409);
  const stored = await client.query('SELECT count(*)::int AS total FROM events WHERE tenant_id=$1', [tenant]);
  assert.equal(stored.rows[0].total, 2);
  const other = await api(baseB, '/api/admin/tenants', 'POST', bootstrap, {id: otherTenant, name: 'Separate tenant'});
  assert.equal(other.status, 201);
  const otherApp = await api(baseB, '/api/tenants/' + otherTenant + '/applications', 'POST', other.data.ownerToken, {id: 'orders'});
  assert.equal(otherApp.status, 201);
  assert.equal((await api(baseA, '/api/tenants/' + otherTenant + '/applications/orders/events/order.created',
    'POST', otherApp.data.publishToken, {orderId: 1}, {'idempotency-key': 'other-1'})).status, 202);
  console.log('Shared PostgreSQL quota passed: two instances accepted exactly two new events, preserved duplicates and isolated tenants.');
} catch (error) { console.error(logs); throw error; }
finally {
  await client.end().catch(() => {});
  for (const child of children) await stopChild(child);
}
