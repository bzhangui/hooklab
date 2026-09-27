'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {providerHeaders} = require('./server.cjs');

test('provider callback sees only bounded protocol headers and rejects ambiguous duplicates', () => {
  const names = JSON.parse(providerHeaders({rawHeaders: [
    'Authorization', 'Bearer private-token', 'Cookie', 'session=private',
    'Content-Type', 'application/json', 'X-Webhook-Signature', 'sha256=' + 'a'.repeat(64),
    'X-Webhook-Id', 'delivery-1',
  ]}));
  assert.deepEqual(names.map(row => row.name), ['content-type', 'x-webhook-signature', 'x-webhook-id']);
  assert.equal(JSON.stringify(names).includes('private-token'), false);
  assert.throws(() => providerHeaders({rawHeaders: [
    'X-Webhook-Signature', 'sha256=' + 'a'.repeat(64),
    'x-webhook-signature', 'sha256=' + 'b'.repeat(64),
  ]}), error => error.code === 'invalid_body');
});
