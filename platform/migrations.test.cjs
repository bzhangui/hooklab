'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {PGlite} = require('@electric-sql/pglite');
const {schemaVersions, runMigrations} = require('./migrations.cjs');

test('fresh schema and existing v1 both migrate to v2 without data loss', async () => {
  for (const old of [false, true]) {
    const db = new PGlite();
    try {
      if (old) {
        await db.exec(fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8'));
        await db.query("INSERT INTO tenants(id,name) VALUES('old','Old')");
      }
      if (old) await assert.rejects(runMigrations(db), /verified backup/);
      assert.equal(await runMigrations(db, {allowUpgrade: old}), 2);
      assert.deepEqual(await schemaVersions(db), [1, 2]);
      assert.equal(await runMigrations(db), 2);
      if (old) assert.equal((await db.query("SELECT name FROM tenants WHERE id='old'")).rows[0].name, 'Old');
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
