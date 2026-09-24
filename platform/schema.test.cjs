'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {PGlite} = require('@electric-sql/pglite');

test('platform schema creates tenant-scoped durable records', async () => {
  const db = new PGlite();
  try {
    await db.exec(fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8'));
    const tables = await db.query("SELECT tablename FROM pg_tables WHERE schemaname='public'");
    for (const name of ['tenants','access_keys','applications','endpoints','subscriptions',
      'event_contracts','events','deliveries','delivery_attempts','audit_entries','alerts']) {
      assert.ok(tables.rows.some(row => row.tablename === name), name);
    }
    await db.query("INSERT INTO tenants(id,name) VALUES('tenant-a','Alice'),('tenant-b','Bob')");
    await db.query("INSERT INTO applications(tenant_id,id,token_hash) VALUES('tenant-a','orders','a'),('tenant-b','orders','b')");
    await db.query(`INSERT INTO events(id,tenant_id,application_id,event_type,idempotency_key,fingerprint,body,trace_id)
      VALUES('00000000-0000-4000-8000-000000000001','tenant-a','orders','order.created','key','fingerprint','{}','a')`);
    await assert.rejects(db.query(`INSERT INTO deliveries(id,tenant_id,event_id,subscription_id,endpoint_id,target_url,
      secret_ciphertext,key_id,state) VALUES('00000000-0000-4000-8000-000000000002','tenant-b',
      '00000000-0000-4000-8000-000000000001','sub','endpoint','https://example.com','cipher','key','pending')`));
  } finally { await db.close(); }
});
