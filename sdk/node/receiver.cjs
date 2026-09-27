'use strict';

const crypto = require('node:crypto');

const required = ['x-hooklab-event-id', 'x-hooklab-delivery-id', 'x-hooklab-event-type',
  'x-hooklab-timestamp', 'x-hooklab-key-id', 'x-hooklab-signature'];
const token = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/;

function normalizedHeaders(input) {
  if (!input || typeof input !== 'object') return null;
  const result = Object.create(null);
  for (const [name, value] of Object.entries(input)) {
    const key = name.toLowerCase();
    if (!required.includes(key)) continue;
    if (Object.hasOwn(result, key) || typeof value !== 'string') return null;
    result[key] = value;
  }
  return result;
}

/** Verify raw bytes before JSON parsing or any business side effect. */
function verifyDelivery({headers, body, secrets, nowMs = Date.now(), toleranceSeconds = 300}) {
  const fields = normalizedHeaders(headers);
  if (!fields || required.some(name => !fields[name])) return {ok: false, code: 'invalid_headers'};
  const [eventId, deliveryId, eventType, timestamp, keyId, signature] =
    required.map(name => fields[name]);
  if (![eventId, deliveryId, eventType, keyId].every(value => token.test(value)) ||
    !/^(0|[1-9][0-9]{0,15})$/.test(timestamp) ||
    !/^v1=[0-9a-f]{64}$/.test(signature)) return {ok: false, code: 'invalid_headers'};
  if (!Number.isFinite(nowMs) || !Number.isSafeInteger(toleranceSeconds) || toleranceSeconds < 0 ||
    toleranceSeconds > 86400) throw new TypeError('Invalid verification clock or tolerance');
  const seconds = Number(timestamp);
  if (!Number.isSafeInteger(seconds) || Math.abs(nowMs / 1000 - seconds) > toleranceSeconds) {
    return {ok: false, code: 'stale_timestamp'};
  }
  if (!Buffer.isBuffer(body) && !(body instanceof Uint8Array)) throw new TypeError('body must be raw bytes');
  const secret = secrets && Object.hasOwn(secrets, keyId) ? secrets[keyId] : undefined;
  if (!(typeof secret === 'string' && secret.length || Buffer.isBuffer(secret) && secret.length)) {
    return {ok: false, code: 'unknown_key'};
  }
  const prefix = Buffer.from(`v1\n${timestamp}\n${deliveryId}\n${eventId}\n${eventType}\n`, 'utf8');
  const expected = crypto.createHmac('sha256', secret).update(prefix).update(body).digest();
  const provided = Buffer.from(signature.slice(3), 'hex');
  if (!crypto.timingSafeEqual(expected, provided)) return {ok: false, code: 'invalid_signature'};
  return {ok: true, eventId, deliveryId, eventType, keyId, timestamp: seconds};
}

module.exports = {verifyDelivery};
