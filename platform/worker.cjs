'use strict';

const crypto = require('node:crypto');
const {postPinned, decryptSecret, newTraceparent} = require('./core.cjs');

function createWorker(pool, callbacks, options = {}) {
  const workerId = options.workerId || 'worker:' + process.pid + ':' + crypto.randomUUID();
  const leaseMs = Math.max(20000, Number(options.leaseMs || 30000));
  const maxParallel = Math.max(1, Math.min(64, Number(options.maxParallel || 8)));
  let active = 0;
  let stopped = false;
  let scanning = false;
  let timer;

  async function claim() {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const result = await client.query(`
        WITH candidate AS (
          SELECT id FROM deliveries
          WHERE (state IN ('pending','scheduled') AND next_attempt_at <= now())
             OR (state='in_flight' AND leased_until <= now())
          ORDER BY next_attempt_at,created_at,id
          FOR UPDATE SKIP LOCKED LIMIT 1
        )
        UPDATE deliveries d SET state='in_flight',attempt=d.attempt+1,
          worker_id=$1,lease_token=$2,leased_until=now()+($3::int * interval '1 millisecond'),updated_at=now()
        FROM candidate WHERE d.id=candidate.id
        RETURNING d.*`, [workerId, crypto.randomUUID(), leaseMs]);
      const item = result.rows[0];
      if (item) {
        // The previous owner may have sent the request before crashing. Its
        // terminal status is unknown, so retain a durable interrupted record.
        await client.query(`UPDATE delivery_attempts SET outcome='interrupted'
          WHERE delivery_id=$1 AND outcome='in_flight'`, [item.id]);
        const attempt = await client.query(`INSERT INTO delivery_attempts
          (tenant_id,delivery_id,attempt,status,outcome,duration_ms)
          VALUES($1,$2,$3,NULL,'in_flight',0) RETURNING id`,
        [item.tenant_id, item.id, item.attempt]);
        item.attempt_record_id = attempt.rows[0].id;
      }
      await client.query('COMMIT');
      return item || null;
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }

  async function deliver(item) {
    const begun = performance.now();
    let status = 0, retryAfter = '', transportError = '';
    const heartbeat = setInterval(() => {
      void pool.query(`UPDATE deliveries SET leased_until=now()+($1::int * interval '1 millisecond')
        WHERE id=$2 AND state='in_flight' AND worker_id=$3 AND lease_token=$4 AND leased_until>now()`,
        [leaseMs, item.id, workerId, item.lease_token]).catch(error => console.error('HookLab lease heartbeat:', error));
    }, Math.floor(leaseMs / 3));
    try {
      const eventResult = await pool.query('SELECT body,event_type,trace_id,content_type FROM events WHERE id=$1', [item.event_id]);
      const event = eventResult.rows[0];
      if (!event) throw new Error('event_missing');
      const timestamp = Math.floor(Date.now() / 1000);
      const secret = decryptSecret(item.secret_ciphertext);
      const signature = callbacks.sign(secret, BigInt(timestamp), item.id, item.event_id, event.event_type, event.body);
      if (!signature) throw new Error('signing_failed');
      const response = await postPinned(item.target_url, {
        'content-type': event.content_type,
        'content-length': Buffer.byteLength(event.body),
        'x-hooklab-event-id': item.event_id,
        'x-hooklab-delivery-id': item.id,
        'x-hooklab-event-type': event.event_type,
        'x-hooklab-key-id': item.key_id,
        'x-hooklab-timestamp': String(timestamp),
        'x-hooklab-signature': signature,
        traceparent: newTraceparent(event.trace_id),
      }, event.body);
      status = response.status;
      retryAfter = response.retryAfter;
    } catch (error) { transportError = String(error && error.message || error).slice(0, 256); }
    finally { clearInterval(heartbeat); }
    let result;
    try { result = JSON.parse(callbacks.decide(item.attempt, status, String(retryAfter), transportError)); }
    catch (_) { result = {decision: 'dead_letter', reason: 'invalid_delivery_decision'}; }
    const durationMs = Math.max(0, Math.round(performance.now() - begun));
    const outcome = result.decision === 'success' ? 'delivered' : result.decision === 'retry' ? 'scheduled' : 'dead_lettered';
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const update = await client.query(`UPDATE deliveries SET state=$1,next_attempt_at=CASE WHEN $1='scheduled' THEN now()+($2::int * interval '1 millisecond') ELSE next_attempt_at END,
        last_status=$3,last_error=$4,worker_id=NULL,lease_token=NULL,leased_until=NULL,updated_at=now()
        WHERE id=$5 AND state='in_flight' AND worker_id=$6 AND lease_token=$7 AND leased_until>now()
        RETURNING tenant_id`, [outcome, Math.max(0, Number(result.delay_ms || 0)), status || null,
          outcome === 'delivered' ? null : (transportError || result.reason || 'HTTP ' + status).slice(0, 256),
          item.id, workerId, item.lease_token]);
      if (update.rowCount) {
        const recorded = await client.query(`UPDATE delivery_attempts
          SET status=$1,outcome=$2,duration_ms=$3
          WHERE id=$4 AND delivery_id=$5 AND attempt=$6 AND outcome='in_flight'`,
        [status || null, outcome, durationMs, item.attempt_record_id, item.id, item.attempt]);
        if (recorded.rowCount !== 1) throw new Error('delivery_attempt_record_missing');
      }
      await client.query('COMMIT');
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }

  async function tick() {
    if (stopped || scanning) return;
    scanning = true;
    try {
      while (!stopped && active < maxParallel) {
        const item = await claim();
        if (!item) break;
        active++;
        void deliver(item).catch(error => console.error('HookLab delivery:', error)).finally(() => { active--; });
      }
    } finally { scanning = false; }
  }

  function start() {
    timer = setInterval(() => { void tick().catch(error => console.error('HookLab worker:', error)); }, 250);
    void tick().catch(error => console.error('HookLab worker:', error));
  }

  function stop() { stopped = true; clearInterval(timer); }
  async function waitForIdle(timeoutMs = 30000) {
    const end = Date.now() + timeoutMs;
    while (active || scanning) {
      if (Date.now() >= end) return false;
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    return true;
  }
  return {start, stop, tick, waitForIdle, get active() { return active; }, workerId};
}

module.exports = {createWorker};
