'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const {createDurableReceiver} = require('./server.cjs');

const secret = 'local-durable-receiver-secret';
const keyId = 'receiver-key';
function headers(body, deliveryId, signatureOverride) {
  const timestamp = String(Math.floor(Date.now() / 1000));
  const eventId = 'event-1', eventType = 'warehouse.updated';
  const signature = 'v1=' + crypto.createHmac('sha256', secret)
    .update(`v1\n${timestamp}\n${deliveryId}\n${eventId}\n${eventType}\n`).update(body).digest('hex');
  return {'content-type': 'application/json', 'x-hooklab-event-id': eventId,
    'x-hooklab-delivery-id': deliveryId, 'x-hooklab-event-type': eventType,
    'x-hooklab-timestamp': timestamp, 'x-hooklab-key-id': keyId,
    'x-hooklab-signature': signatureOverride || signature};
}
async function start(dbPath) {
  const receiver = createDurableReceiver({dbPath, secret, keyId});
  await new Promise(resolve => receiver.server.listen(0, '127.0.0.1', resolve));
  return {receiver, url: `http://127.0.0.1:${receiver.server.address().port}/events`};
}

test('verified delivery and inventory effect commit once across receiver restarts', async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hooklab-durable-test-'));
  const dbPath = path.join(temp, 'receiver.sqlite');
  let running;
  try {
    running = await start(dbPath);
    const first = Buffer.from(JSON.stringify({itemId: 'part-1', stock: 7}));
    const send = (body, id, signatureOverride) => fetch(running.url, {method: 'POST',
      headers: headers(body, id, signatureOverride), body});
    assert.equal((await send(first, 'delivery-1', 'v1=' + '0'.repeat(64))).status, 401);
    assert.equal(running.receiver.db.prepare('SELECT count(*) AS total FROM processed_deliveries').get().total, 0);
    assert.equal((await send(Buffer.from('{"bad":true}'), 'delivery-1')).status, 422);
    assert.equal((await send(first, 'delivery-1')).status, 204);
    assert.equal(running.receiver.db.prepare('SELECT stock FROM inventory WHERE item_id=?').get('part-1').stock, 7);
    await running.receiver.close();
    running = await start(dbPath);
    // A repeated attempt carries the same delivery ID and must not repeat the business write.
    assert.equal((await send(first, 'delivery-1')).status, 204);
    assert.equal((await send(Buffer.from(JSON.stringify({itemId: 'part-1', stock: 99})), 'delivery-1')).status, 409);
    assert.equal(running.receiver.db.prepare('SELECT stock FROM inventory WHERE item_id=?').get('part-1').stock, 7);
    assert.equal((await send(Buffer.from(JSON.stringify({itemId: 'part-1', stock: 8})), 'delivery-2')).status, 204);
    assert.equal(running.receiver.db.prepare('SELECT stock FROM inventory WHERE item_id=?').get('part-1').stock, 8);
    assert.equal(running.receiver.db.prepare('SELECT count(*) AS total FROM processed_deliveries').get().total, 2);
  } finally {
    if (running && running.receiver.server.listening) await running.receiver.close();
    if (path.resolve(temp).startsWith(path.resolve(os.tmpdir()) + path.sep)) fs.rmSync(temp, {recursive: true, force: true});
  }
});
