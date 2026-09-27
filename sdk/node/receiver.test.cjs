'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {verifyDelivery} = require('./receiver.cjs');

const body = Buffer.from('{"message":"hello\\nHookLab"}', 'utf8');
const headers = {
  'x-hooklab-timestamp': '1700000000',
  'x-hooklab-delivery-id': 'delivery:demo',
  'x-hooklab-event-id': 'publish:demo',
  'x-hooklab-event-type': 'order.created',
  'x-hooklab-key-id': 'key-v1',
  // Canonical vector also asserted by hooklab/outbound/outbound_test.mbt.
  'x-hooklab-signature': 'v1=978a6161dd2b90f1a4576d6982447e4e45c0fea27ec2a414fcf3c487549172e0',
};
const options = {headers, body, secrets: {'key-v1': 'test-secret'}, nowMs: 1700000000 * 1000};

test('Node receiver matches the MoonBit canonical vector and raw UTF-8 bytes', () => {
  assert.deepEqual(verifyDelivery(options), {ok: true, eventId: 'publish:demo',
    deliveryId: 'delivery:demo', eventType: 'order.created', keyId: 'key-v1', timestamp: 1700000000});
  const prefix = 'v1\n1700000000\ndelivery:demo\npublish:demo\norder.created\n';
  assert.equal('v1=' + crypto.createHmac('sha256', 'test-secret').update(prefix).update(body).digest('hex'),
    headers['x-hooklab-signature']);
});

test('receiver rejects tampering, stale timestamps, unknown keys and ambiguous headers', () => {
  assert.equal(verifyDelivery({...options, body: Buffer.from('{}')}).code, 'invalid_signature');
  assert.equal(verifyDelivery({...options, nowMs: options.nowMs + 301000}).code, 'stale_timestamp');
  assert.equal(verifyDelivery({...options, secrets: {}}).code, 'unknown_key');
  assert.equal(verifyDelivery({...options, headers: {...headers, 'X-HookLab-Signature': headers['x-hooklab-signature']}}).code,
    'invalid_headers');
  assert.equal(verifyDelivery({...options, headers: {...headers, 'x-hooklab-event-type': 'order\ncreated'}}).code,
    'invalid_headers');
  assert.equal(verifyDelivery({...options, headers: {...headers, 'x-hooklab-signature': 'v1=' + '0'.repeat(64)}}).code,
    'invalid_signature');
  assert.throws(() => verifyDelivery({...options, body: '{}'}), /raw bytes/);
});
