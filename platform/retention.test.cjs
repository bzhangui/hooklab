'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {PGlite} = require('@electric-sql/pglite');
const {runMigrations} = require('./migrations.cjs');
const {policy, previewRetention, applyRetention} = require('./retention.cjs');

const nowMs = Date.parse('2026-09-27T00:00:00.000Z');
const old = '2026-07-01T00:00:00.000Z';
const recent = '2026-09-20T00:00:00.000Z';
const uuid = digit => '00000000-0000-4000-8000-' + digit.repeat(12);

test('retention preview is read-only and apply removes only old terminal tenant data', async () => {
  const db = new PGlite();
  try {
    await runMigrations(db);
    await db.query("INSERT INTO tenants(id,name) VALUES('alice','Alice'),('bob','Bob')");
    await db.query("INSERT INTO applications(tenant_id,id,token_hash) VALUES('alice','orders','a'),('bob','orders','b')");
    for (const [digit, tenant, created] of [['1','alice',old],['2','alice',old],['3','alice',recent],
      ['4','bob',old],['5','alice',old],['6','alice',old]]) {
      await db.query(`INSERT INTO events(id,tenant_id,application_id,event_type,idempotency_key,fingerprint,body,trace_id,created_at)
        VALUES($1,$2,'orders','order.created',$3,'fp','{}','trace',$4)`, [uuid(digit), tenant, digit, created]);
    }
    for (const [digit, state, updated] of [['1','delivered',old],['2','pending',old],
      ['3','delivered',recent],['5','delivered',recent],['6','dead_lettered',old]]) {
      await db.query(`INSERT INTO deliveries(id,tenant_id,event_id,subscription_id,endpoint_id,target_url,
        secret_ciphertext,key_id,state,created_at,updated_at) VALUES($1,'alice',$2,$3,'receiver','https://example.com','cipher','key',$4,$5,$6)`,
      [uuid(String.fromCharCode(96 + Number(digit))), uuid(digit), digit, state, old, updated]);
    }
    await db.query(`INSERT INTO delivery_attempts(tenant_id,delivery_id,attempt,outcome,duration_ms)
      VALUES('alice',$1,1,'delivered',4)`, [uuid('a')]);
    const settings = {tenantId: 'alice', days: 30, nowMs, limit: 1};
    assert.equal((await previewRetention(db, settings)).eligibleEvents, 2);
    assert.equal((await db.query('SELECT count(*)::int AS count FROM events')).rows[0].count, 6);
    assert.deepEqual(await applyRetention(db, settings), {mode: 'apply', tenantId: 'alice',
      cutoff: '2026-08-28T00:00:00.000Z', deletedEvents: 1, deletedDeliveries: 1, deletedAttempts: 1});
    assert.equal((await db.query('SELECT count(*)::int AS count FROM events')).rows[0].count, 5);
    assert.equal((await previewRetention(db, settings)).eligibleEvents, 1);
    assert.equal((await applyRetention(db, settings)).deletedEvents, 1);
    assert.equal((await previewRetention(db, settings)).eligibleEvents, 0);
    assert.equal((await db.query('SELECT count(*)::int AS count FROM events')).rows[0].count, 4);
    assert.equal((await db.query("SELECT count(*)::int AS count FROM events WHERE tenant_id='bob'")).rows[0].count, 1);
    assert.equal((await db.query("SELECT count(*)::int AS count FROM audit_entries WHERE action='events.purged'")).rows[0].count, 2);
  } finally { await db.close(); }
});

test('retention policy rejects unbounded and too-short deletion', () => {
  assert.throws(() => policy({tenantId: 'alice', days: 7}), /30/);
  assert.throws(() => policy({tenantId: 'alice', days: 30, limit: 501}), /500/);
  assert.throws(() => policy({tenantId: 'bad id', days: 30}), /tenant/);
});
