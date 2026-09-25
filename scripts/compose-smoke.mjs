import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

assert.equal(process.env.CI, 'true', 'Synthetic database seeding is only for disposable CI deployments');
const root = path.resolve(import.meta.dirname, '..');
const values = Object.fromEntries(fs.readFileSync(path.join(root, '.env'), 'utf8')
  .split(/\r?\n/).filter(Boolean).map(line => line.split('=', 2)));
const base = 'http://127.0.0.1:' + (values.HOOKLAB_PORT || '8787');
const tenant = 'ci-smoke-' + crypto.randomBytes(4).toString('hex');
async function post(route, token, body, headers = {}) {
  const response = await fetch(base + route, {method: 'POST', headers: {
    authorization: 'Bearer ' + token, 'content-type': 'application/json', ...headers,
  }, body: JSON.stringify(body)});
  return {status: response.status, data: await response.json()};
}
const created = await post('/api/admin/tenants', values.HOOKLAB_BOOTSTRAP_TOKEN, {id: tenant, name: 'CI synthetic tenant'});
assert.equal(created.status, 201);
const app = await post('/api/tenants/' + tenant + '/applications', created.data.ownerToken, {id: 'orders'});
assert.equal(app.status, 201);
const event = await post('/api/tenants/' + tenant + '/applications/orders/events/order.created',
  app.data.publishToken, {orderId: 1}, {'idempotency-key': 'ci-order-1'});
assert.equal(event.status, 202);
const response = await fetch(base + '/api/tenants/' + tenant + '/events',
  {headers: {authorization: 'Bearer ' + created.data.ownerToken}});
assert.equal(response.status, 200);
assert.ok((await response.json()).some(row => row.id === event.data.eventId));
console.log('Disposable Compose deployment accepted and persisted a synthetic order event.');
