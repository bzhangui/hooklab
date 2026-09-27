import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {PGlite} from '@electric-sql/pglite';
import {runMigrations} from '../platform/migrations.cjs';
import {exportHistory, validateBundle, importHistory} from './sqlite-transfer.mjs';

test('SQLite transfer previews, imports only history and safely reruns', async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hooklab-transfer-test-'));
  const file = path.join(temp, 'old.sqlite');
  const sqlite = new DatabaseSync(file);
  const target = new PGlite();
  try {
    sqlite.exec(`CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
      INSERT INTO metadata VALUES('schema_version','1');
      CREATE TABLE events(id TEXT PRIMARY KEY,source TEXT,provider TEXT,event_type TEXT,body TEXT,received_at INTEGER);
      CREATE TABLE deliveries(id TEXT PRIMARY KEY,state TEXT);
      INSERT INTO events VALUES('legacy-one','ingress','generic-hmac','warehouse.updated','{"itemId":"part-1"}',1790000000000);
      INSERT INTO deliveries VALUES('delivery-old','delivered');`);
    const bundle = exportHistory(file);
    assert.equal(validateBundle(bundle).records.length, 1);
    assert.throws(() => validateBundle({...bundle, checksum: '0'.repeat(64)}), /modified/);
    await runMigrations(target);
    await target.query("INSERT INTO tenants(id,name) VALUES('acme','Acme')");
    await target.query("INSERT INTO applications(tenant_id,id,token_hash) VALUES('acme','incoming','hash')");
    const options = {tenantId: 'acme', applicationId: 'incoming'};
    assert.equal((await importHistory(target, bundle, options)).newEvents, 1);
    assert.equal((await target.query('SELECT count(*)::int AS total FROM events')).rows[0].total, 0);
    assert.equal((await importHistory(target, bundle, {...options, apply: true})).newEvents, 1);
    assert.equal((await importHistory(target, bundle, {...options, apply: true})).existingEvents, 1);
    const imported = await target.query('SELECT source,provider,body FROM events');
    assert.deepEqual(imported.rows, [{source: 'provider', provider: 'generic-hmac', body: '{"itemId":"part-1"}'}]);
    assert.equal((await target.query('SELECT count(*)::int AS total FROM deliveries')).rows[0].total, 0);
    sqlite.exec("INSERT INTO deliveries VALUES('unfinished','pending')");
    assert.throws(() => exportHistory(file), /non-terminal/);
  } finally {
    sqlite.close();
    await target.close();
    if (path.resolve(temp).startsWith(path.resolve(os.tmpdir()) + path.sep)) fs.rmSync(temp, {recursive: true, force: true});
  }
});
