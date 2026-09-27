'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {createDemoReceiver} = require('./server.cjs');

test('loopback receiver verifies and deduplicates two signed HTTP attempts', async () => {
  const accepted = [];
  const {server} = createDemoReceiver({secret: 'local-test-secret', keyId: 'key-v1',
    onAccepted: (type, id) => accepted.push({type, id})});
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = 'http://127.0.0.1:' + server.address().port + '/events';
  try {
    const body = '{"orderId":42}';
    const timestamp = String(Math.floor(Date.now() / 1000));
    const message = `v1\n${timestamp}\ndelivery:one\npublish:one\norder.created\n${body}`;
    const headers = {'x-hooklab-timestamp': timestamp, 'x-hooklab-delivery-id': 'delivery:one',
      'x-hooklab-event-id': 'publish:one', 'x-hooklab-event-type': 'order.created',
      'x-hooklab-key-id': 'key-v1', 'x-hooklab-signature': 'v1=' + crypto.createHmac('sha256', 'local-test-secret')
        .update(message).digest('hex')};
    assert.equal((await fetch(url, {method: 'POST', headers, body})).status, 204);
    assert.equal((await fetch(url, {method: 'POST', headers, body})).status, 204);
    assert.deepEqual(accepted, [{type: 'order.created', id: 'delivery:one'}]);
    assert.equal((await fetch(url, {method: 'POST', headers, body: '{}'})).status, 401);
    assert.equal((await fetch(url, {method: 'POST', headers: {...headers, 'x-hooklab-signature': 'v1=' + '0'.repeat(64)}, body})).status, 401);
    assert.equal(accepted.length, 1);
  } finally { await new Promise(resolve => server.close(resolve)); }
});
