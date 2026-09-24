'use strict';

const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const {Pool} = require('pg');
const {createWorker} = require('./worker.cjs');
const core = require('./core.cjs');

const roles = {viewer: 1, developer: 2, owner: 3};
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const statusByCode = {invalid_json: 422, invalid_body: 422, invalid_id: 422, invalid_target_url: 422,
  unsafe_target_url: 422, target_resolves_to_nonpublic_address: 422, invalid_schema: 422,
  invalid_contract: 422, invalid_cloudevent: 422, invalid_cloudevent_source: 422,
  invalid_cloudevent_data: 422, invalid_cloudevent_time: 422,
  contract_violation: 422, unsupported_media_type: 415, missing_idempotency_key: 400,
  unauthorized: 401, forbidden: 403, not_found: 404, conflict: 409, payload_too_large: 413};

function failure(code, details) {
  const error = new Error(code);
  error.code = code;
  error.status = statusByCode[code] || 500;
  if (details) error.details = details;
  return error;
}
function assert(condition, code) { if (!condition) throw failure(code); }
function bearer(req) {
  const value = String(req.headers.authorization || '');
  return value.startsWith('Bearer ') ? value.slice(7) : '';
}
function send(res, status, value) {
  const body = JSON.stringify(value);
  res.writeHead(status, {'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store', 'x-content-type-options': 'nosniff', 'referrer-policy': 'no-referrer'});
  res.end(body);
}
function sendText(res, status, body, type) {
  res.writeHead(status, {'content-type': type, 'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store', 'x-content-type-options': 'nosniff', 'referrer-policy': 'no-referrer',
    'content-security-policy': "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'"});
  res.end(body);
}
async function bodyText(req) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 1024 * 1024) throw failure('payload_too_large');
    chunks.push(chunk);
  }
  try { return new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks)); }
  catch (_) { throw failure('invalid_body'); }
}
async function jsonBody(req) {
  const text = await bodyText(req);
  try { const value = JSON.parse(text); assert(value && typeof value === 'object' && !Array.isArray(value), 'invalid_body'); return value; }
  catch (error) { if (error.status) throw error; throw failure('invalid_json'); }
}
function validId(value) { return typeof value === 'string' && core.idPattern.test(value); }
function jsonValue(value) { return value && typeof value === 'object' && !Array.isArray(value); }
function safeError(error) { return {error: error.code || 'internal_error', ...(error.details ? {details: error.details} : {})}; }
function tokenHashFromHeader(req) { const token = bearer(req); return token ? core.hashToken(token) : ''; }
function schemaCompatible(previous, next) {
  if (!previous.type && next.type) return false;
  if (previous.type && next.type && previous.type !== next.type && !(previous.type === 'integer' && next.type === 'number')) return false;
  if (next.enum && (!previous.enum || previous.enum.some(value => !next.enum.some(candidate => JSON.stringify(candidate) === JSON.stringify(value))))) return false;
  if (previous.type === 'object') {
    for (const key of next.required || []) if (!(previous.required || []).includes(key)) return false;
    for (const [key, oldChild] of Object.entries(previous.properties || {})) {
      const newChild = (next.properties || {})[key];
      if (!newChild && next.additionalProperties === false) return false;
      if (newChild && !schemaCompatible(oldChild, newChild)) return false;
    }
    if (previous.additionalProperties !== false) {
      for (const key of Object.keys(next.properties || {})) {
        if (!Object.hasOwn(previous.properties || {}, key)) return false;
      }
    }
    if (previous.additionalProperties !== false && next.additionalProperties === false) return false;
  }
  if (previous.type === 'array' && !previous.items && next.items) return false;
  if (previous.type === 'array' && previous.items && next.items && !schemaCompatible(previous.items, next.items)) return false;
  return true;
}

async function startPlatform(options) {
  core.encryptionKey();
  assert(process.env.HOOKLAB_BOOTSTRAP_TOKEN && process.env.HOOKLAB_BOOTSTRAP_TOKEN.length >= 32, 'bootstrap_token_required');
  assert(process.env.HOOKLAB_METRICS_TOKEN && process.env.HOOKLAB_METRICS_TOKEN.length >= 32, 'metrics_token_required');
  const pool = new Pool({connectionString: process.env.DATABASE_URL, max: 12,
    connectionTimeoutMillis: 5000, idleTimeoutMillis: 30000});
  pool.on('error', error => console.error('HookLab PostgreSQL pool:', error));
  const migration = await pool.connect();
  try {
    await migration.query('SELECT pg_advisory_lock(90261860)');
    const version = await migration.query("SELECT to_regclass('public.hooklab_schema') AS name");
    if (version.rows[0].name) {
      const current = await migration.query('SELECT max(version) AS version FROM hooklab_schema');
      if (Number(current.rows[0].version) > 1) throw new Error('Database schema is newer than this HookLab version');
    }
    await migration.query(fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8'));
    await migration.query('SELECT pg_advisory_unlock(90261860)');
  } catch (error) { try { await migration.query('SELECT pg_advisory_unlock(90261860)'); } catch (_) {} await pool.end(); throw error; }
  finally { migration.release(); }

  const callbacks = options.callbacks;
  const worker = createWorker(pool, callbacks, {maxParallel: process.env.HOOKLAB_MAX_WORKERS});
  const query = (sql, params = []) => pool.query(sql, params);
  async function transaction(fn) {
    const client = await pool.connect();
    try { await client.query('BEGIN'); const value = await fn(client); await client.query('COMMIT'); return value; }
    catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }
  async function audit(client, tenantId, actor, action, resource) {
    await client.query('INSERT INTO audit_entries(tenant_id,actor,action,resource) VALUES($1,$2,$3,$4)',
      [tenantId, actor, action, resource]);
  }
  async function authorized(req, tenantId, minimum = 'viewer') {
    const hash = tokenHashFromHeader(req);
    assert(hash, 'unauthorized');
    const result = await query('SELECT id,role FROM access_keys WHERE tenant_id=$1 AND token_hash=$2 AND revoked_at IS NULL', [tenantId, hash]);
    const key = result.rows[0];
    assert(key, 'unauthorized');
    assert(roles[key.role] >= roles[minimum], 'forbidden');
    return key;
  }
  function safeMutationOrigin(req) {
    const origin = req.headers.origin;
    if (!origin) return;
    const host = req.headers.host;
    let parsed;
    try { parsed = new URL(String(origin)); } catch (_) { throw failure('forbidden'); }
    assert(parsed.host === host && ['http:', 'https:'].includes(parsed.protocol), 'forbidden');
  }
  async function control(req, res, tenantId, segments, url) {
    const method = req.method;
    const resource = segments[0] || '';
    const mutation = method !== 'GET';
    if (mutation) safeMutationOrigin(req);
    const key = await authorized(req, tenantId, mutation ? 'developer' : 'viewer');
    const actor = String(key.id);
    if (method === 'GET' && resource === 'catalog' && segments.length === 1) {
      const [apps, endpoints, subs, contracts] = await Promise.all([
        query('SELECT id,enabled,created_at FROM applications WHERE tenant_id=$1 ORDER BY id', [tenantId]),
        query('SELECT id,url,key_id,enabled,created_at FROM endpoints WHERE tenant_id=$1 ORDER BY id', [tenantId]),
        query('SELECT id,application_id,endpoint_id,event_types,enabled FROM subscriptions WHERE tenant_id=$1 ORDER BY id', [tenantId]),
        query('SELECT application_id,event_type,version,require_cloudevents,active FROM event_contracts WHERE tenant_id=$1 ORDER BY application_id,event_type,version DESC', [tenantId]),
      ]);
      return send(res, 200, {applications: apps.rows, endpoints: endpoints.rows, subscriptions: subs.rows, contracts: contracts.rows});
    }
    if (method === 'GET' && resource === 'contracts' && segments.length === 1) {
      const rows = await query(`SELECT application_id,event_type,version,schema_json,require_cloudevents,active,created_at
        FROM event_contracts WHERE tenant_id=$1 ORDER BY application_id,event_type,version DESC LIMIT 100`, [tenantId]);
      return send(res, 200, rows.rows);
    }
    if (method === 'POST' && resource === 'keys' && segments.length === 1) {
      assert(key.role === 'owner', 'forbidden');
      const body = await jsonBody(req);
      assert(Object.hasOwn(roles, body.role) && typeof body.label === 'string' && body.label.length <= 80, 'invalid_body');
      const token = core.makeToken(), id = crypto.randomUUID();
      await transaction(async client => {
        await client.query('INSERT INTO access_keys(id,tenant_id,role,token_hash,label) VALUES($1,$2,$3,$4,$5)',
          [id, tenantId, body.role, core.hashToken(token), body.label]);
        await audit(client, tenantId, actor, 'key.created', id);
      });
      return send(res, 201, {id, role: body.role, token});
    }
    if (method === 'POST' && resource === 'keys' && segments.length === 3 && segments[2] === 'revoke') {
      assert(key.role === 'owner', 'forbidden');
      const id = segments[1];
      assert(uuidPattern.test(id), 'invalid_id');
      assert(id !== actor, 'conflict');
      const updated = await transaction(async client => {
        const result = await client.query('UPDATE access_keys SET revoked_at=now() WHERE tenant_id=$1 AND id=$2 AND revoked_at IS NULL RETURNING id', [tenantId, id]);
        if (result.rowCount) await audit(client, tenantId, actor, 'key.revoked', id);
        return result.rowCount;
      });
      assert(updated, 'not_found');
      return send(res, 200, {revoked: true});
    }
    if (method === 'POST' && resource === 'applications' && segments.length === 1) {
      const body = await jsonBody(req);
      assert(validId(body.id), 'invalid_id');
      const token = core.makeToken();
      await transaction(async client => {
        await client.query('INSERT INTO applications(tenant_id,id,token_hash) VALUES($1,$2,$3)', [tenantId, body.id, core.hashToken(token)]);
        await audit(client, tenantId, actor, 'application.created', body.id);
      });
      return send(res, 201, {id: body.id, publishToken: token});
    }
    if (method === 'POST' && resource === 'applications' && segments.length === 3 && segments[2] === 'rotate-token') {
      const token = core.makeToken(), id = segments[1];
      const updated = await transaction(async client => {
        const result = await client.query('UPDATE applications SET token_hash=$1 WHERE tenant_id=$2 AND id=$3 RETURNING id', [core.hashToken(token), tenantId, id]);
        if (result.rowCount) await audit(client, tenantId, actor, 'application.token_rotated', id);
        return result.rowCount;
      });
      assert(updated, 'not_found');
      return send(res, 200, {id, publishToken: token});
    }
    if (method === 'POST' && resource === 'endpoints' && segments.length === 1) {
      const body = await jsonBody(req);
      assert(validId(body.id) && typeof body.url === 'string', 'invalid_body');
      const target = core.targetUrl(body.url);
      await core.resolvedTarget(target);
      const secret = core.makeToken(), keyId = 'key-' + crypto.randomBytes(8).toString('hex');
      await transaction(async client => {
        await client.query('INSERT INTO endpoints(tenant_id,id,url,secret_ciphertext,key_id) VALUES($1,$2,$3,$4,$5)',
          [tenantId, body.id, target.toString(), core.encryptSecret(secret), keyId]);
        await audit(client, tenantId, actor, 'endpoint.created', body.id);
      });
      return send(res, 201, {id: body.id, url: target.toString(), keyId, signingSecret: secret});
    }
    if (method === 'POST' && resource === 'endpoints' && segments.length === 3 && segments[2] === 'rotate-secret') {
      const id = segments[1], secret = core.makeToken(), keyId = 'key-' + crypto.randomBytes(8).toString('hex');
      const updated = await transaction(async client => {
        const result = await client.query('UPDATE endpoints SET secret_ciphertext=$1,key_id=$2 WHERE tenant_id=$3 AND id=$4 RETURNING id',
          [core.encryptSecret(secret), keyId, tenantId, id]);
        if (result.rowCount) await audit(client, tenantId, actor, 'endpoint.secret_rotated', id);
        return result.rowCount;
      });
      assert(updated, 'not_found');
      return send(res, 200, {id, keyId, signingSecret: secret});
    }
    if (method === 'POST' && resource === 'subscriptions' && segments.length === 1) {
      const body = await jsonBody(req);
      assert(validId(body.id) && validId(body.applicationId) && validId(body.endpointId) && Array.isArray(body.eventTypes) && body.eventTypes.length > 0 && body.eventTypes.length <= 32 && body.eventTypes.every(x => x === '*' || typeof x === 'string' && core.eventTypePattern.test(x)), 'invalid_body');
      await transaction(async client => {
        await client.query('INSERT INTO subscriptions(tenant_id,id,application_id,endpoint_id,event_types) VALUES($1,$2,$3,$4,$5)',
          [tenantId, body.id, body.applicationId, body.endpointId, JSON.stringify(body.eventTypes)]);
        await audit(client, tenantId, actor, 'subscription.created', body.id);
      });
      return send(res, 201, {id: body.id});
    }
    if (method === 'PATCH' && ['applications','endpoints','subscriptions'].includes(resource) && segments.length === 2) {
      const body = await jsonBody(req);
      assert(typeof body.enabled === 'boolean' && Object.keys(body).length === 1, 'invalid_body');
      const id = segments[1];
      const updated = await transaction(async client => {
        const result = await client.query(`UPDATE ${resource} SET enabled=$1 WHERE tenant_id=$2 AND id=$3 RETURNING id`, [body.enabled, tenantId, id]);
        if (result.rowCount) await audit(client, tenantId, actor, resource.slice(0,-1) + '.enabled_changed', id);
        return result.rowCount;
      });
      assert(updated, 'not_found');
      return send(res, 200, {id, enabled: body.enabled});
    }
    if (method === 'POST' && resource === 'contracts' && segments.length === 1) {
      const body = await jsonBody(req);
      assert(validId(body.applicationId) && typeof body.eventType === 'string' && core.eventTypePattern.test(body.eventType) &&
        Number.isSafeInteger(body.version) && body.version > 0 && typeof body.requireCloudEvents === 'boolean' && core.checkSchemaDefinition(body.schema), 'invalid_schema');
      await transaction(async client => {
        const application = await client.query('SELECT id FROM applications WHERE tenant_id=$1 AND id=$2 FOR UPDATE', [tenantId, body.applicationId]);
        assert(application.rowCount, 'not_found');
        const prior = await client.query(`SELECT version,schema_json,require_cloudevents FROM event_contracts WHERE tenant_id=$1 AND application_id=$2 AND event_type=$3
          ORDER BY version DESC LIMIT 1 FOR UPDATE`, [tenantId, body.applicationId, body.eventType]);
        if (prior.rowCount && (body.version <= prior.rows[0].version ||
          !schemaCompatible(prior.rows[0].schema_json, body.schema) ||
          !prior.rows[0].require_cloudevents && body.requireCloudEvents)) throw failure('conflict');
        await client.query('UPDATE event_contracts SET active=false WHERE tenant_id=$1 AND application_id=$2 AND event_type=$3', [tenantId, body.applicationId, body.eventType]);
        await client.query(`INSERT INTO event_contracts(tenant_id,application_id,event_type,version,schema_json,require_cloudevents)
          VALUES($1,$2,$3,$4,$5,$6)`, [tenantId, body.applicationId, body.eventType, body.version, JSON.stringify(body.schema), body.requireCloudEvents]);
        await audit(client, tenantId, actor, 'contract.published', body.applicationId + ':' + body.eventType + ':' + body.version);
      });
      return send(res, 201, {applicationId: body.applicationId, eventType: body.eventType, version: body.version});
    }
    if (method === 'GET' && resource === 'events' && segments.length === 1) {
      const rows = await query(`SELECT id,application_id,event_type,trace_id,created_at FROM events WHERE tenant_id=$1 ORDER BY created_at DESC,id DESC LIMIT 100`, [tenantId]);
      return send(res, 200, rows.rows);
    }
    if (method === 'GET' && resource === 'deliveries' && segments.length === 1) {
      const rows = await query(`SELECT id,event_id,subscription_id,endpoint_id,target_url,state,attempt,next_attempt_at,last_status,last_error,created_at,updated_at
        FROM deliveries WHERE tenant_id=$1 ORDER BY created_at DESC,id DESC LIMIT 100`, [tenantId]);
      return send(res, 200, rows.rows);
    }
    if (method === 'GET' && resource === 'deliveries' && segments.length === 3 && segments[2] === 'attempts') {
      assert(uuidPattern.test(segments[1]), 'invalid_id');
      const rows = await query(`SELECT attempt,status,outcome,duration_ms,created_at FROM delivery_attempts
        WHERE tenant_id=$1 AND delivery_id=$2 ORDER BY attempt DESC LIMIT 100`, [tenantId, segments[1]]);
      return send(res, 200, rows.rows);
    }
    if (method === 'POST' && resource === 'deliveries' && segments.length === 3 && segments[2] === 'retry') {
      const id = segments[1];
      assert(uuidPattern.test(id), 'invalid_id');
      const updated = await transaction(async client => {
        const result = await client.query(`UPDATE deliveries SET state='pending',attempt=0,next_attempt_at=now(),last_error='manual retry',updated_at=now()
          WHERE tenant_id=$1 AND id=$2 AND state='dead_lettered' RETURNING id`, [tenantId,id]);
        if (result.rowCount) await audit(client, tenantId, actor, 'delivery.retried', id);
        return result.rowCount;
      });
      assert(updated, 'conflict');
      return send(res, 202, {id, state: 'pending'});
    }
    if (method === 'GET' && resource === 'audit' && segments.length === 1) {
      const rows = await query('SELECT id,actor,action,resource,created_at FROM audit_entries WHERE tenant_id=$1 ORDER BY id DESC LIMIT 100', [tenantId]);
      return send(res, 200, rows.rows);
    }
    if (method === 'GET' && resource === 'alerts' && segments.length === 1) {
      const rows = await query('SELECT id,kind,state,message,opened_at,resolved_at FROM alerts WHERE tenant_id=$1 ORDER BY id DESC LIMIT 100', [tenantId]);
      return send(res, 200, rows.rows);
    }
    if (method === 'GET' && resource === 'slo' && segments.length === 1) {
      const total = await query(`SELECT count(*)::int AS total,count(*) FILTER (WHERE state='delivered')::int AS delivered,
        count(*) FILTER (WHERE state='dead_lettered')::int AS dead_lettered FROM deliveries
        WHERE tenant_id=$1 AND created_at >= now()-interval '24 hours'`, [tenantId]);
      const row = total.rows[0];
      const latency = await query(`SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms) AS p95_ms
        FROM delivery_attempts WHERE tenant_id=$1 AND created_at >= now()-interval '24 hours'`, [tenantId]);
      return send(res, 200, {window: '24h', total: row.total, delivered: row.delivered,
        deadLettered: row.dead_lettered, deliverySuccessRatio: row.total ? row.delivered / row.total : null,
        p95AttemptLatencyMs: latency.rows[0].p95_ms === null ? null : Number(latency.rows[0].p95_ms),
        target: 0.99, note: 'Accepted deliveries, including work still pending, are in the denominator.'});
    }
    return send(res, 404, {error: 'not_found'});
  }

  async function publish(req, res, tenantId, appId, eventType) {
    assert(core.eventTypePattern.test(eventType), 'invalid_id');
    const token = bearer(req);
    assert(token, 'unauthorized');
    const appResult = await query('SELECT token_hash,enabled FROM applications WHERE tenant_id=$1 AND id=$2', [tenantId, appId]);
    const app = appResult.rows[0];
    assert(app && app.enabled && core.tokenMatches(app.token_hash, token), 'unauthorized');
    const idempotencyKey = String(req.headers['idempotency-key'] || '').trim();
    assert(idempotencyKey && idempotencyKey.length <= 128 && !/[\r\n]/.test(idempotencyKey), 'missing_idempotency_key');
    const mediaType = String(req.headers['content-type'] || '').split(';')[0].trim().toLowerCase();
    assert(mediaType === 'application/json' || mediaType === 'application/cloudevents+json', 'unsupported_media_type');
    const raw = await bodyText(req);
    let value;
    try { value = JSON.parse(raw); } catch (_) { throw failure('invalid_json'); }
    const contractResult = await query(`SELECT schema_json,require_cloudevents,version FROM event_contracts
      WHERE tenant_id=$1 AND application_id=$2 AND event_type=$3 AND active=true ORDER BY version DESC LIMIT 1`,
    [tenantId, appId, eventType]);
    const contract = contractResult.rows[0];
    let data = value;
    if (mediaType === 'application/cloudevents+json' || contract && contract.require_cloudevents) {
      assert(mediaType === 'application/cloudevents+json', 'unsupported_media_type');
      const parsed = core.structuredCloudEvent(value, eventType);
      if (!parsed.ok) throw failure(parsed.code);
      data = parsed.data;
    }
    if (contract) {
      const issues = core.validateSchema(contract.schema_json, data);
      if (issues.length) throw failure('contract_violation', issues);
    }
    let moonbitValidation;
    try { moonbitValidation = JSON.parse(callbacks.validate(raw, mediaType, eventType,
      contract ? JSON.stringify(contract.schema_json) : '', Boolean(contract && contract.require_cloudevents))); }
    catch (_) { throw failure('internal_error'); }
    if (!moonbitValidation.valid) throw failure('contract_violation', moonbitValidation.issues || []);
    const catalog = await query(`SELECT s.id AS subscription_id,e.id AS endpoint_id,e.url,e.key_id,e.secret_ciphertext
      FROM subscriptions s JOIN endpoints e ON e.tenant_id=s.tenant_id AND e.id=s.endpoint_id
      WHERE s.tenant_id=$1 AND s.application_id=$2 AND s.enabled AND e.enabled AND (s.event_types ? $3 OR s.event_types ? '*') ORDER BY s.id`,
    [tenantId, appId, eventType]);
    let plan;
    try { plan = JSON.parse(callbacks.plan(appId, eventType, idempotencyKey, raw, JSON.stringify(catalog.rows))); }
    catch (_) { throw failure('internal_error'); }
    assert(plan.accepted && Array.isArray(plan.subscriptions), 'invalid_contract');
    const fingerprint = crypto.createHash('sha256').update(mediaType + '\n' + eventType + '\n' + raw).digest('hex');
    const trace = core.traceId(req.headers.traceparent);
    const created = await transaction(async client => {
      const existing = await client.query(`SELECT id,fingerprint FROM events WHERE tenant_id=$1 AND application_id=$2 AND idempotency_key=$3 FOR UPDATE`, [tenantId, appId, idempotencyKey]);
      if (existing.rowCount) {
        if (existing.rows[0].fingerprint !== fingerprint) throw failure('conflict');
        return {accepted: true, duplicate: true, eventId: existing.rows[0].id, deliveries: 0};
      }
      const eventId = crypto.randomUUID();
      const inserted = await client.query(`INSERT INTO events(id,tenant_id,application_id,event_type,idempotency_key,fingerprint,body,content_type,trace_id)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT(tenant_id,application_id,idempotency_key) DO NOTHING RETURNING id`,
      [eventId, tenantId, appId, eventType, idempotencyKey, fingerprint, raw, mediaType, trace]);
      if (!inserted.rowCount) {
        const raced = await client.query('SELECT id,fingerprint FROM events WHERE tenant_id=$1 AND application_id=$2 AND idempotency_key=$3', [tenantId, appId, idempotencyKey]);
        if (raced.rows[0].fingerprint !== fingerprint) throw failure('conflict');
        return {accepted: true, duplicate: true, eventId: raced.rows[0].id, deliveries: 0};
      }
      for (const item of catalog.rows) {
        if (!plan.subscriptions.includes(item.subscription_id)) continue;
        await client.query(`INSERT INTO deliveries(id,tenant_id,event_id,subscription_id,endpoint_id,target_url,secret_ciphertext,key_id,state)
          VALUES($1,$2,$3,$4,$5,$6,$7,$8,'pending')`,
        [crypto.randomUUID(), tenantId, eventId, item.subscription_id, item.endpoint_id, item.url, item.secret_ciphertext, item.key_id]);
      }
      return {accepted: true, duplicate: false, eventId, deliveries: plan.subscriptions.length};
    });
    return send(res, created.duplicate ? 200 : 202, created);
  }

  async function evaluateAlerts() {
    const tenants = await query('SELECT id FROM tenants');
    for (const tenant of tenants.rows) {
      const result = await query(`SELECT count(*) FILTER (WHERE state='dead_lettered' AND updated_at >= now()-interval '1 hour')::int AS dead,
        count(*) FILTER (WHERE state IN ('pending','scheduled') AND created_at < now()-interval '5 minutes')::int AS stale
        FROM deliveries WHERE tenant_id=$1`, [tenant.id]);
      for (const [kind, triggered, message] of [
        ['dead_letters', result.rows[0].dead > 0, 'At least one delivery entered the dead letter queue in the last hour.'],
        ['stale_backlog', result.rows[0].stale > 0, 'At least one pending delivery has waited over five minutes.'],
      ]) {
        if (triggered) await query(`INSERT INTO alerts(tenant_id,kind,state,message) VALUES($1,$2,'open',$3)
          ON CONFLICT(tenant_id,kind) WHERE state='open' DO NOTHING`, [tenant.id, kind, message]);
        else await query("UPDATE alerts SET state='resolved',resolved_at=now() WHERE tenant_id=$1 AND kind=$2 AND state='open'", [tenant.id,kind]);
      }
    }
  }

  async function metrics(req, res) {
    assert(core.tokenMatches(core.hashToken(process.env.HOOKLAB_METRICS_TOKEN), bearer(req)), 'unauthorized');
    const states = await query('SELECT state,count(*)::int AS count FROM deliveries GROUP BY state');
    const attempts = await query("SELECT outcome,count(*)::int AS count FROM delivery_attempts WHERE created_at >= now()-interval '24 hours' GROUP BY outcome");
    const durations = await query(`SELECT count(*)::int AS total,coalesce(sum(duration_ms),0)::bigint AS total_ms,
      count(*) FILTER (WHERE duration_ms <= 100)::int AS le100,
      count(*) FILTER (WHERE duration_ms <= 500)::int AS le500,
      count(*) FILTER (WHERE duration_ms <= 1000)::int AS le1000,
      count(*) FILTER (WHERE duration_ms <= 5000)::int AS le5000,
      count(*) FILTER (WHERE duration_ms <= 15000)::int AS le15000 FROM delivery_attempts`);
    const backlog = await query(`SELECT coalesce(extract(epoch FROM now()-min(created_at)),0)::int AS oldest_seconds
      FROM deliveries WHERE state IN ('pending','scheduled')`);
    const openAlerts = await query("SELECT count(*)::int AS count FROM alerts WHERE state='open'");
    const lines = ['# HELP hooklab_deliveries Current deliveries by state', '# TYPE hooklab_deliveries gauge'];
    for (const row of states.rows) lines.push(`hooklab_deliveries{state="${row.state}"} ${row.count}`);
    lines.push('# HELP hooklab_delivery_attempts_24h Delivery attempts in the last 24 hours', '# TYPE hooklab_delivery_attempts_24h gauge');
    for (const row of attempts.rows) lines.push(`hooklab_delivery_attempts_24h{outcome="${row.outcome}"} ${row.count}`);
    const histogram = durations.rows[0];
    lines.push('# HELP hooklab_delivery_duration_ms End-to-end HTTP attempt duration in milliseconds', '# TYPE hooklab_delivery_duration_ms histogram');
    for (const [limit, column] of [['100','le100'],['500','le500'],['1000','le1000'],['5000','le5000'],['15000','le15000']]) {
      lines.push(`hooklab_delivery_duration_ms_bucket{le="${limit}"} ${histogram[column]}`);
    }
    lines.push(`hooklab_delivery_duration_ms_bucket{le="+Inf"} ${histogram.total}`,
      `hooklab_delivery_duration_ms_sum ${histogram.total_ms}`, `hooklab_delivery_duration_ms_count ${histogram.total}`,
      '# HELP hooklab_backlog_oldest_age_seconds Age of oldest pending or scheduled delivery',
      '# TYPE hooklab_backlog_oldest_age_seconds gauge', `hooklab_backlog_oldest_age_seconds ${backlog.rows[0].oldest_seconds}`,
      '# HELP hooklab_open_alerts Open local alert conditions', '# TYPE hooklab_open_alerts gauge',
      `hooklab_open_alerts ${openAlerts.rows[0].count}`);
    lines.push('# HELP hooklab_worker_active Active deliveries in this process', '# TYPE hooklab_worker_active gauge', `hooklab_worker_active ${worker.active}`);
    sendText(res, 200, lines.join('\n') + '\n', 'text/plain; version=0.0.4; charset=utf-8');
  }

  const handler = async (req, res) => {
    const url = new URL(req.url || '/', 'http://localhost');
    const segments = url.pathname.split('/').filter(Boolean);
    if (req.method === 'GET' && url.pathname === '/health') {
      await query('SELECT 1');
      return send(res, 200, {status: 'ok', storage: 'postgresql', schemaVersion: 1, workerId: worker.workerId});
    }
    if (req.method === 'GET' && url.pathname === '/metrics') return metrics(req, res);
    if (req.method === 'GET' && url.pathname === '/') return sendText(res, 200,
      fs.readFileSync(path.join(__dirname, 'portal.html'), 'utf8'), 'text/html; charset=utf-8');
    if (req.method === 'GET' && url.pathname === '/portal.js') return sendText(res, 200,
      fs.readFileSync(path.join(__dirname, 'portal.js'), 'utf8'), 'text/javascript; charset=utf-8');
    if (req.method === 'GET' && url.pathname === '/portal.css') return sendText(res, 200,
      fs.readFileSync(path.join(__dirname, 'portal.css'), 'utf8'), 'text/css; charset=utf-8');
    if (req.method === 'POST' && url.pathname === '/api/admin/tenants') {
      safeMutationOrigin(req);
      assert(core.tokenMatches(core.hashToken(process.env.HOOKLAB_BOOTSTRAP_TOKEN), bearer(req)), 'unauthorized');
      const body = await jsonBody(req);
      assert(validId(body.id) && typeof body.name === 'string' && body.name.trim() && body.name.length <= 100, 'invalid_body');
      const ownerToken = core.makeToken(), keyId = crypto.randomUUID();
      await transaction(async client => {
        await client.query('INSERT INTO tenants(id,name) VALUES($1,$2)', [body.id,body.name.trim()]);
        await client.query("INSERT INTO access_keys(id,tenant_id,role,token_hash,label) VALUES($1,$2,'owner',$3,'initial owner')",
          [keyId,body.id,core.hashToken(ownerToken)]);
        await audit(client, body.id, 'bootstrap', 'tenant.created', body.id);
      });
      return send(res, 201, {id: body.id, ownerToken});
    }
    if (segments[0] === 'api' && segments[1] === 'tenants' && validId(segments[2])) {
      const tenantId = segments[2], tail = segments.slice(3);
      if (req.method === 'POST' && tail[0] === 'applications' && tail[2] === 'events' && tail.length === 4) {
        safeMutationOrigin(req);
        return publish(req, res, tenantId, tail[1], tail[3]);
      }
      return control(req, res, tenantId, tail, url);
    }
    return send(res, 404, {error: 'not_found'});
  };
  const server = http.createServer((req, res) => {
    void handler(req, res).catch(error => {
      if (!error.status && statusByCode[error.message]) error = failure(error.message);
      if (!error.status && error.code !== '23505' && error.code !== '23503') console.error('HookLab platform request:', error);
      if (error.code === '23505' || error.code === '23503') error = failure('conflict');
      if (!res.headersSent) send(res, error.status || 500, safeError(error));
      else res.destroy();
    });
  });
  server.requestTimeout = 20000;
  server.headersTimeout = 10000;
  const host = process.env.HOOKLAB_BIND_HOST || '127.0.0.1';
  const port = Number(options.port || 8787);
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, host, resolve); });
  worker.start();
  const alertIntervalMs = Math.max(500, Number(process.env.HOOKLAB_ALERT_INTERVAL_MS || 60000));
  const alertTimer = setInterval(() => { void evaluateAlerts().catch(error => console.error('HookLab alert evaluation:', error)); }, alertIntervalMs);
  void evaluateAlerts().catch(error => console.error('HookLab alert evaluation:', error));
  return {server, pool, worker, close: async () => {
    clearInterval(alertTimer); worker.stop();
    await new Promise(resolve => server.close(resolve));
    await worker.waitForIdle();
    await pool.end();
  }};
}

module.exports = {startPlatform, schemaCompatible};
