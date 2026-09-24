'use strict';

const crypto = require('node:crypto');
const dns = require('node:dns').promises;
const https = require('node:https');
const http = require('node:http');
const ipaddr = require('ipaddr.js');

const idPattern = /^[a-z][a-z0-9_-]{1,63}$/;
const eventTypePattern = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/;
const traceparentPattern = /^00-([0-9a-f]{32})-([0-9a-f]{16})-0[1-9a-f]$/;

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function tokenMatches(storedHash, token) {
  if (!storedHash || !token) return false;
  const actual = Buffer.from(hashToken(token), 'hex');
  const expected = Buffer.from(storedHash, 'hex');
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}

function makeToken() {
  return 'hkl_' + crypto.randomBytes(32).toString('base64url');
}

function encryptionKey() {
  const raw = process.env.HOOKLAB_ENCRYPTION_KEY || '';
  if (!/^[0-9a-fA-F]{64}$/.test(raw)) throw new Error('HOOKLAB_ENCRYPTION_KEY must be 32 bytes encoded as 64 hex characters');
  return Buffer.from(raw, 'hex');
}

function encryptSecret(secret) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(secret, 'utf8'), cipher.final()]);
  return [iv, cipher.getAuthTag(), ciphertext].map(x => x.toString('base64url')).join('.');
}

function decryptSecret(value) {
  const parts = value.split('.');
  if (parts.length !== 3) throw new Error('Invalid encrypted secret');
  const [iv, tag, ciphertext] = parts.map(x => Buffer.from(x, 'base64url'));
  const decipher = crypto.createDecipheriv('aes-256-gcm', encryptionKey(), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
}

function isPublicAddress(address) {
  try {
    const parsed = ipaddr.parse(address);
    if (parsed.kind() === 'ipv6' && parsed.isIPv4MappedAddress()) return parsed.toIPv4Address().range() === 'unicast';
    return parsed.range() === 'unicast';
  } catch (_) { return false; }
}

function targetUrl(value) {
  let url;
  try { url = new URL(value); } catch (_) { throw new Error('invalid_target_url'); }
  const loopbackTest = process.env.HOOKLAB_ALLOW_LOOPBACK_ENDPOINTS === '1' &&
    url.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if ((url.protocol !== 'https:' && !loopbackTest) || url.username || url.password || url.hash || url.search || !url.hostname) {
    throw new Error('unsafe_target_url');
  }
  return url;
}

async function resolvedTarget(url) {
  const addresses = await dns.lookup(url.hostname.replace(/^\[|\]$/g, ''), {all: true});
  const allowLoopback = process.env.HOOKLAB_ALLOW_LOOPBACK_ENDPOINTS === '1' && url.protocol === 'http:' &&
    ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if (!addresses.length || addresses.some(item => !isPublicAddress(item.address) && !(allowLoopback && ['127.0.0.1', '::1'].includes(item.address)))) {
    throw new Error('target_resolves_to_nonpublic_address');
  }
  return addresses[0];
}

async function postPinned(urlString, headers, body, timeoutMs = 15000) {
  const url = targetUrl(urlString);
  const pinned = await resolvedTarget(url);
  const transport = url.protocol === 'https:' ? https : http;
  return new Promise((resolve, reject) => {
    const req = transport.request(url, {
      method: 'POST', headers,
      lookup: (_hostname, _options, callback) => callback(null, pinned.address, pinned.family),
      timeout: timeoutMs,
    }, response => {
      response.resume();
      response.on('end', () => resolve({status: response.statusCode || 0, retryAfter: response.headers['retry-after'] || ''}));
    });
    req.on('timeout', () => req.destroy(new Error('delivery_timeout')));
    req.on('error', reject);
    req.end(body);
  });
}

function traceId(traceparent) {
  const match = traceparentPattern.exec(String(traceparent || ''));
  return match && match[1] !== '0'.repeat(32) ? match[1] : crypto.randomBytes(16).toString('hex');
}

function newTraceparent(trace) {
  return '00-' + trace + '-' + crypto.randomBytes(8).toString('hex') + '-01';
}

function structuredCloudEvent(payload, eventType) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return {ok: false, code: 'invalid_cloudevent'};
  if (payload.specversion !== '1.0' || typeof payload.id !== 'string' || !payload.id ||
    typeof payload.source !== 'string' || !payload.source ||
    typeof payload.type !== 'string' || payload.type !== eventType) return {ok: false, code: 'invalid_cloudevent'};
  try { new URL(payload.source, 'https://hooklab.invalid/'); } catch (_) { return {ok: false, code: 'invalid_cloudevent_source'}; }
  // Binary data is not yet a delivery format in this UTF-8 JSON adapter.
  if (payload.data_base64 !== undefined) return {ok: false, code: 'invalid_cloudevent_data'};
  if (payload.time !== undefined && (typeof payload.time !== 'string' || !Number.isFinite(Date.parse(payload.time)))) return {ok: false, code: 'invalid_cloudevent_time'};
  return {ok: true, data: payload.data === undefined ? null : payload.data};
}

// Deliberately small, documented JSON Schema subset. Unknown keywords are
// rejected when a contract is saved rather than silently ignored at publish.
const schemaKeywords = new Set(['type', 'required', 'properties', 'items', 'enum', 'additionalProperties']);
const schemaTypes = new Set(['object', 'array', 'string', 'number', 'integer', 'boolean', 'null']);
function checkSchemaDefinition(schema, depth = 0) {
  if (!schema || typeof schema !== 'object' || Array.isArray(schema) || depth > 16) return false;
  for (const key of Object.keys(schema)) if (!schemaKeywords.has(key)) return false;
  if (schema.type !== undefined && !schemaTypes.has(schema.type)) return false;
  if (schema.required !== undefined && (!Array.isArray(schema.required) || schema.required.some(x => typeof x !== 'string'))) return false;
  if (schema.enum !== undefined && (!Array.isArray(schema.enum) || schema.enum.length === 0)) return false;
  if (schema.additionalProperties !== undefined && typeof schema.additionalProperties !== 'boolean') return false;
  if (schema.properties !== undefined && (!schema.properties || typeof schema.properties !== 'object' || Array.isArray(schema.properties) || Object.values(schema.properties).some(x => !checkSchemaDefinition(x, depth + 1)))) return false;
  if (schema.items !== undefined && !checkSchemaDefinition(schema.items, depth + 1)) return false;
  return true;
}

function validateSchema(schema, value, path = '$', depth = 0) {
  if (depth > 32) return [{path, code: 'max_depth'}];
  const issues = [];
  const type = value === null ? 'null' : Array.isArray(value) ? 'array' : Number.isInteger(value) ? 'integer' : typeof value;
  if (schema.type && !(schema.type === type || schema.type === 'number' && type === 'integer')) issues.push({path, code: 'type'});
  if (schema.enum && !schema.enum.some(candidate => JSON.stringify(candidate) === JSON.stringify(value))) issues.push({path, code: 'enum'});
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    for (const key of schema.required || []) if (!Object.hasOwn(value, key)) issues.push({path: path + '.' + key, code: 'required'});
    for (const [key, child] of Object.entries(value)) {
      if (schema.properties && Object.hasOwn(schema.properties, key)) issues.push(...validateSchema(schema.properties[key], child, path + '.' + key, depth + 1));
      else if (schema.additionalProperties === false) issues.push({path: path + '.' + key, code: 'additional_property'});
    }
  }
  if (Array.isArray(value) && schema.items) for (let i = 0; i < value.length; i++) issues.push(...validateSchema(schema.items, value[i], path + '[' + i + ']', depth + 1));
  return issues.slice(0, 50);
}

module.exports = {idPattern, eventTypePattern, hashToken, tokenMatches, makeToken, encryptionKey, encryptSecret, decryptSecret, targetUrl, resolvedTarget, isPublicAddress, postPinned, traceId, newTraceparent, structuredCloudEvent, checkSchemaDefinition, validateSchema};
