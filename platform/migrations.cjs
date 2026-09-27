'use strict';

const fs = require('node:fs');
const path = require('node:path');

const latestVersion = 2;
const sql = name => fs.readFileSync(path.join(__dirname, name), 'utf8');
const runSql = (client, source) => typeof client.exec === 'function' ? client.exec(source) : client.query(source);
const tables = ['hooklab_schema', 'tenants', 'access_keys', 'applications', 'endpoints',
  'subscriptions', 'event_contracts', 'events', 'deliveries', 'delivery_attempts',
  'audit_entries', 'alerts'];

async function assertShape(client, version = 2) {
  const result = await client.query(`SELECT ${tables.map(name => `to_regclass('public.${name}') AS ${name}`).join(', ')},
    to_regclass('public.events_retention_idx') AS retention_index`);
  for (const name of tables) if (!result.rows[0][name]) throw new Error('Missing HookLab table: ' + name);
  if (version >= 2 && !result.rows[0].retention_index) throw new Error('Missing HookLab retention index');
}

async function schemaVersions(client) {
  const present = await client.query(`SELECT ${tables.map(name => `to_regclass('public.${name}') AS ${name}`).join(', ')}`);
  if (!present.rows[0].hooklab_schema) {
    if (tables.some(name => name !== 'hooklab_schema' && present.rows[0][name])) {
      throw new Error('HookLab tables exist without a schema marker; refuse automatic repair');
    }
    return null;
  }
  const result = await client.query('SELECT version FROM hooklab_schema ORDER BY version');
  return result.rows.map(row => Number(row.version));
}

async function runMigrations(client, {allowUpgrade = false} = {}) {
  let versions = await schemaVersions(client);
  const fresh = versions === null;
  if (versions !== null && !(versions.length === 1 && versions[0] === 1 ||
    versions.length === 2 && versions[0] === 1 && versions[1] === 2)) {
    throw new Error('Unsupported or incomplete HookLab schema version history: ' + versions.join(','));
  }
  if (versions === null) {
    await client.query('BEGIN');
    try { await runSql(client, sql('schema.sql')); await client.query('COMMIT'); }
    catch (error) { await client.query('ROLLBACK'); throw error; }
    versions = [1];
  }
  if (versions.at(-1) === 1) {
    await assertShape(client, 1);
    if (!fresh && !allowUpgrade) {
      throw new Error('Schema v1 upgrade requires HOOKLAB_ALLOW_SCHEMA_UPGRADE=1 after a verified backup');
    }
    await client.query('BEGIN');
    try { await runSql(client, sql('migrations/002_retention_index.sql')); await client.query('COMMIT'); }
    catch (error) { await client.query('ROLLBACK'); throw error; }
  }
  const final = await schemaVersions(client);
  if (final.join(',') !== '1,2') throw new Error('HookLab schema migration did not finish');
  await assertShape(client);
  return latestVersion;
}

module.exports = {schemaVersions, runMigrations, latestVersion};
