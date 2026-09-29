import assert from 'node:assert/strict';
import test from 'node:test';
import {firstEventRequest} from './first-event.mjs';

const input = {tenant: 'trial', application: 'orders', type: 'order.created',
  port: 8787, token: 'a'.repeat(32), body: '{"orderId":"HL-demo-001"}', key: 'test-key'};

test('first event uses loopback, scoped path and idempotency without logging secrets', () => {
  const request = firstEventRequest(input);
  assert.equal(request.url, 'http://127.0.0.1:8787/api/tenants/trial/applications/orders/events/order.created');
  assert.equal(request.options.headers['idempotency-key'], 'test-key');
  assert.equal(request.options.body, input.body);
});

test('first event rejects invalid identifiers, body and missing token before network I/O', () => {
  assert.throws(() => firstEventRequest({...input, tenant: '../admin'}), /格式/);
  assert.throws(() => firstEventRequest({...input, body: '{'}), SyntaxError);
  assert.throws(() => firstEventRequest({...input, token: ''}), /HOOKLAB_PUBLISH_TOKEN/);
});
