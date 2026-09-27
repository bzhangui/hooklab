'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {PGlite} = require('@electric-sql/pglite');
const {schemaVersions, runMigrations} = require('./migrations.cjs');

test('fresh schema and existing v1/v2 both migrate to v3 without data loss', async () => {
  for (const old of [0, 1, 2]) {
    const db = new PGlite();
    try {
      if (old) {
        await db.exec(fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8'));
        if (old === 2) await db.exec(fs.readFileSync(path.join(__dirname, 'migrations/002_retention_index.sql'), 'utf8'));
        await db.query("INSERT INTO tenants(id,name) VALUES('old','Old')");
      }
      if (old) await assert.rejects(runMigrations(db), /verified backup/);
      assert.equal(await runMigrations(db, {allowUpgrade: Boolean(old)}), 3);
      assert.deepEqual(await schemaVersions(db), [1, 2, 3]);
      assert.equal(await runMigrations(db), 3);
      if (old) assert.equal((await db.query("SELECT name FROM tenants WHERE id='old'")).rows[0].name, 'Old');
      const table = await db.query("SELECT to_regclass('public.provider_credentials') AS name");
      assert.equal(table.rows[0].name, 'provider_credentials');
    } finally { await db.close(); }
  }
});

test('future and partial schema histories fail closed', async () => {
  const db = new PGlite();
  try {
    await db.exec(fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8'));
    await db.query('INSERT INTO hooklab_schema(version) VALUES(9)');
    await assert.rejects(runMigrations(db), /Unsupported/);
    await db.query('DELETE FROM hooklab_schema');
    await assert.rejects(runMigrations(db), /Unsupported/);
  } finally { await db.close(); }
});
