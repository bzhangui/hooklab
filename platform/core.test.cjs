'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const core = require('./core.cjs');

test('tokens compare by hash and secrets round-trip without plaintext storage', () => {
  process.env.HOOKLAB_ENCRYPTION_KEY = 'a'.repeat(64);
  const token = core.makeToken();
  const hash = core.hashToken(token);
  assert.equal(core.tokenMatches(hash, token), true);
  assert.equal(core.tokenMatches(hash, token + 'x'), false);
  const cipher = core.encryptSecret(token);
  assert.equal(cipher.includes(token), false);
  assert.equal(core.decryptSecret(cipher), token);
  assert.throws(() => core.decryptSecret(cipher.slice(0, -2) + 'xx'));
});

test('endpoint policy rejects private targets and URL credentials', () => {
  assert.equal(core.isPublicAddress('8.8.8.8'), true);
  for (const ip of ['127.0.0.1','10.0.0.1','192.168.1.1','169.254.169.254','::1','fe80::1','fc00::1','::ffff:127.0.0.1']) {
    assert.equal(core.isPublicAddress(ip), false, ip);
  }
  assert.throws(() => core.targetUrl('http://example.com/hook'));
  assert.throws(() => core.targetUrl('https://user:pass@example.com/hook'));
  assert.throws(() => core.targetUrl('https://example.com/hook?token=secret'));
  assert.equal(core.targetUrl('https://example.com/hook').hostname, 'example.com');
});

test('structured CloudEvents are checked before contracts', () => {
  const good = {specversion: '1.0', id: 'e-1', source: '/orders', type: 'order.created', data: {id: 4}};
  assert.deepEqual(core.structuredCloudEvent(good, 'order.created'), {ok: true, data: {id: 4}});
  assert.equal(core.structuredCloudEvent({...good, type: 'other'}, 'order.created').ok, false);
  assert.equal(core.structuredCloudEvent({...good, specversion: '0.3'}, 'order.created').ok, false);
  assert.equal(core.structuredCloudEvent({...good, data_base64: 'eA=='}, 'order.created').ok, false);
});

test('contract subset rejects unsupported keywords and validates nested data', () => {
  const schema = {type: 'object', required: ['id'], additionalProperties: false,
    properties: {id: {type: 'integer'}, items: {type: 'array', items: {type: 'string'}}}};
  assert.equal(core.checkSchemaDefinition(schema), true);
  assert.equal(core.checkSchemaDefinition({...schema, pattern: 'x'}), false);
  assert.deepEqual(core.validateSchema(schema, {id: 1, items: ['x']}), []);
  assert.deepEqual(core.validateSchema(schema, {items: [2], extra: true}).map(x => x.code).sort(),
    ['additional_property','required','type']);
});

test('trace context preserves valid trace identifiers only', () => {
  const valid = '00-' + 'a'.repeat(32) + '-' + 'b'.repeat(16) + '-01';
  assert.equal(core.traceId(valid), 'a'.repeat(32));
  assert.match(core.traceId('invalid'), /^[0-9a-f]{32}$/);
  assert.match(core.newTraceparent('a'.repeat(32)), /^00-a{32}-[0-9a-f]{16}-01$/);
});
