import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

assert.equal(process.env.CI, 'true', 'Synthetic database seeding is only for disposable CI deployments');
const root = path.resolve(import.meta.dirname, '..');
const values = Object.fromEntries(fs.readFileSync(path.join(root, '.env'), 'utf8')
  .split(/\r?\n/).filter(Boolean).map(line => line.split('=', 2)));
const base = 'http://127.0.0.1:' + (values.HOOKLAB_PORT || '8787');
const receiver = 'http://127.0.0.1:8766';
const tenant = 'ci-smoke-' + crypto.randomBytes(4).toString('hex');
async function until(check, timeoutMs = 60000) {
  const end = Date.now() + timeoutMs;
  let last;
  while (Date.now() < end) {
    try { const result = await check(); if (result) return result; }
    catch (error) { last = error; }
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  throw last || new Error('Timed out waiting for container delivery');
}
async function post(route, token, body, headers = {}) {
  const response = await fetch(base + route, {method: 'POST', headers: {
    authorization: 'Bearer ' + token, 'content-type': 'application/json', ...headers,
  }, body: JSON.stringify(body)});
  return {status: response.status, data: await response.json()};
}
async function get(route, token) {
  const response = await fetch(base + route, {headers: {authorization: 'Bearer ' + token}});
  return {status: response.status, data: await response.json()};
}
await until(async () => (await fetch(receiver + '/health')).ok);
const created = await post('/api/admin/tenants', values.HOOKLAB_BOOTSTRAP_TOKEN, {id: tenant, name: 'CI synthetic tenant'});
assert.equal(created.status, 201);
const route = '/api/tenants/' + tenant;
const app = await post('/api/tenants/' + tenant + '/applications', created.data.ownerToken, {id: 'orders'});
assert.equal(app.status, 201);
const endpoint = await post(route + '/endpoints', created.data.ownerToken,
  {id: 'warehouse', url: 'http://127.0.0.1:8766/sink'});
assert.equal(endpoint.status, 201);
assert.equal((await post(route + '/subscriptions', created.data.ownerToken,
  {id: 'orders-to-warehouse', applicationId: 'orders', endpointId: 'warehouse', eventTypes: ['order.created']})).status, 201);
assert.equal((await post(route + '/contracts', created.data.ownerToken,
  {applicationId: 'orders', eventType: 'order.created', version: 1, requireCloudEvents: false,
    schema: {type: 'object', required: ['orderId'], properties: {orderId: {type: 'integer'}}}})).status, 201);
const publishRoute = route + '/applications/orders/events/order.created';
const headers = {'idempotency-key': 'ci-order-1'};
const rejected = await post(publishRoute, app.data.publishToken, {orderId: 'invalid'}, headers);
assert.equal(rejected.status, 422);
const payload = {orderId: 1};
const event = await post(publishRoute, app.data.publishToken, payload, headers);
assert.equal(event.status, 202);
assert.equal(event.data.deliveries, 1);
const delivery = await until(async () => {
  const response = await get(route + '/deliveries', created.data.ownerToken);
  assert.equal(response.status, 200);
  return response.data.find(row => row.event_id === event.data.eventId && row.state === 'delivered');
});
const received = await until(async () => {
  const response = await fetch(receiver + '/state');
  assert.equal(response.status, 200);
  const rows = await response.json();
  return rows.length >= 2 ? rows : null;
});
assert.equal(received.length, 2);
for (const attempt of received) {
  const fields = attempt.headers;
  assert.equal(fields['x-hooklab-event-id'], event.data.eventId);
  assert.equal(fields['x-hooklab-delivery-id'], delivery.id);
  assert.equal(fields['x-hooklab-event-type'], 'order.created');
  assert.equal(fields['x-hooklab-key-id'], endpoint.data.keyId);
  assert.deepEqual(JSON.parse(attempt.body), payload);
  const signed = 'v1\n' + fields['x-hooklab-timestamp'] + '\n' + delivery.id + '\n' +
    event.data.eventId + '\norder.created\n' + attempt.body;
  const expected = 'v1=' + crypto.createHmac('sha256', endpoint.data.signingSecret).update(signed).digest('hex');
  assert.equal(fields['x-hooklab-signature'], expected);
}
const attempts = await get(route + '/deliveries/' + delivery.id + '/attempts', created.data.ownerToken);
assert.equal(attempts.status, 200);
assert.deepEqual(attempts.data.map(row => [row.attempt, row.status, row.outcome]),
  [[2, 204, 'delivered'], [1, 503, 'scheduled']]);
const duplicate = await post(publishRoute, app.data.publishToken, payload, headers);
assert.equal(duplicate.status, 200);
assert.equal(duplicate.data.eventId, event.data.eventId);
assert.equal((await get(route + '/events', created.data.ownerToken)).data.filter(row => row.id === event.data.eventId).length, 1);
assert.equal((await (await fetch(receiver + '/state')).json()).length, 2);
console.log('Disposable Compose deployment rejected an invalid event, delivered a signed retry to the receiver, and suppressed an idempotent duplicate.');
