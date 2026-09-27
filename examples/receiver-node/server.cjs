'use strict';

// Deliberately loopback-only and in-memory: a local integration example, not
// a production deduplication store or a public webhook endpoint.
const http = require('node:http');
const {verifyDelivery} = require('../../sdk/node/receiver.cjs');

function createDemoReceiver({secret, keyId, onAccepted = console.log}) {
  if (!secret || !keyId) throw new Error('Set HOOKLAB_RECEIVER_SECRET and HOOKLAB_RECEIVER_KEY_ID');
  const seen = new Set();
  const server = http.createServer(async (request, response) => {
    if (request.method !== 'POST' || request.url !== '/events') {
      response.writeHead(404).end();
      return;
    }
    try {
      const chunks = [];
      let size = 0;
      for await (const chunk of request) {
        size += chunk.length;
        if (size > 1024 * 1024) { response.writeHead(413).end(); return; }
        chunks.push(chunk);
      }
      const raw = Buffer.concat(chunks);
      const result = verifyDelivery({headers: request.headers, body: raw, secrets: {[keyId]: secret}});
      if (!result.ok) { response.writeHead(401).end(); return; }
      if (!seen.has(result.deliveryId)) {
        if (seen.size >= 10000) { response.writeHead(503).end(); return; }
        // In a real consumer, insert the delivery ID and perform the business
        // effect in the SAME durable transaction before acknowledging it.
        await onAccepted(result.eventType, result.deliveryId);
        seen.add(result.deliveryId);
      }
      response.writeHead(204).end();
    } catch (error) {
      console.error('Receiver failed:', error);
      if (!response.headersSent) response.writeHead(500).end();
    }
  });
  return {server, seen};
}

if (require.main === module) {
  const {server} = createDemoReceiver({secret: process.env.HOOKLAB_RECEIVER_SECRET,
    keyId: process.env.HOOKLAB_RECEIVER_KEY_ID});
  server.listen(9090, '127.0.0.1', () => console.log('Demo receiver: http://127.0.0.1:9090/events'));
}
module.exports = {createDemoReceiver};
