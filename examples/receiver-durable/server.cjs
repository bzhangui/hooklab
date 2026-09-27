'use strict';

// A local, durable consumer pattern. Replace the inventory write with your
// own business transaction, keeping deduplication in that same transaction.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const {DatabaseSync} = require('node:sqlite');
const {verifyDelivery} = require('../../sdk/node/receiver.cjs');

function createDurableReceiver({dbPath, secret, keyId, consumerId = 'inventory'}) {
  if (!dbPath || !secret || !keyId || !/^[a-z][a-z0-9_-]{1,63}$/.test(consumerId)) {
    throw new Error('Set a database path, secret, key ID and valid consumer ID');
  }
  fs.mkdirSync(path.dirname(path.resolve(dbPath)), {recursive: true});
  const db = new DatabaseSync(dbPath);
  db.exec('PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000');
  db.exec(`CREATE TABLE IF NOT EXISTS processed_deliveries (
    consumer_id TEXT NOT NULL, delivery_id TEXT NOT NULL,
    event_id TEXT NOT NULL, fingerprint TEXT NOT NULL,
    received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(consumer_id,delivery_id));
    CREATE TABLE IF NOT EXISTS inventory (
    item_id TEXT PRIMARY KEY, stock INTEGER NOT NULL, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);`);
  const insertDelivery = db.prepare('INSERT OR IGNORE INTO processed_deliveries(consumer_id,delivery_id,event_id,fingerprint) VALUES(?,?,?,?)');
  const priorDelivery = db.prepare('SELECT fingerprint FROM processed_deliveries WHERE consumer_id=? AND delivery_id=?');
  const updateInventory = db.prepare(`INSERT INTO inventory(item_id,stock) VALUES(?,?)
    ON CONFLICT(item_id) DO UPDATE SET stock=excluded.stock,updated_at=CURRENT_TIMESTAMP`);
  const server = http.createServer(async (request, response) => {
    if (request.method !== 'POST' || request.url !== '/events') return response.writeHead(404).end();
    try {
      const chunks = [];
      let bytes = 0;
      for await (const chunk of request) {
        bytes += chunk.length;
        if (bytes > 1024 * 1024) return response.writeHead(413).end();
        chunks.push(chunk);
      }
      const raw = Buffer.concat(chunks);
      const result = verifyDelivery({headers: request.headers, body: raw, secrets: {[keyId]: secret}});
      if (!result.ok) return response.writeHead(401).end();
      if (result.eventType !== 'warehouse.updated') return response.writeHead(422).end();
      let value;
      try { value = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(raw)); }
      catch (_) { return response.writeHead(422).end(); }
      if (!value || typeof value !== 'object' || Array.isArray(value) ||
        typeof value.itemId !== 'string' || !/^[a-zA-Z0-9_-]{1,64}$/.test(value.itemId) ||
        !Number.isSafeInteger(value.stock) || value.stock < 0) return response.writeHead(422).end();
      const fingerprint = crypto.createHash('sha256')
        .update(result.eventId + '\n' + result.eventType + '\n').update(raw).digest('hex');
      db.exec('BEGIN IMMEDIATE');
      try {
        const inserted = insertDelivery.run(consumerId, result.deliveryId, result.eventId, fingerprint);
        if (inserted.changes) updateInventory.run(value.itemId, value.stock);
        else if (priorDelivery.get(consumerId, result.deliveryId).fingerprint !== fingerprint) {
          db.exec('ROLLBACK');
          return response.writeHead(409).end();
        }
        db.exec('COMMIT');
      } catch (error) { db.exec('ROLLBACK'); throw error; }
      response.writeHead(204).end();
    } catch (error) {
      console.error('Durable receiver failed:', error.message);
      if (!response.headersSent) response.writeHead(503).end();
    }
  });
  return {server, db, close: async () => {
    await new Promise(resolve => server.close(resolve));
    db.close();
  }};
}

if (require.main === module) {
  const receiver = createDurableReceiver({dbPath: process.env.HOOKLAB_RECEIVER_DB || './receiver-data/receiver.sqlite',
    secret: process.env.HOOKLAB_RECEIVER_SECRET, keyId: process.env.HOOKLAB_RECEIVER_KEY_ID});
  receiver.server.listen(9090, '127.0.0.1', () => console.log('Durable receiver: http://127.0.0.1:9090/events'));
  process.once('SIGINT', () => { void receiver.close(); });
  process.once('SIGTERM', () => { void receiver.close(); });
}

module.exports = {createDurableReceiver};
