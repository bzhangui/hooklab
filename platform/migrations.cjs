'use strict';

const fs = require('node:fs');
const path = require('node:path');

const latestVersion = 3;
const sql = name => fs.readFileSync(path.join(__dirname, name), 'utf8');
const runSql = (client, source) => typeof client.exec === 'function' ? client.exec(source) : client.query(source);
const tables = ['hooklab_schema', 'tenants', 'access_keys', 'applications', 'endpoints',
  'subscriptions', 'event_contracts', 'events', 'deliveries', 'delivery_attempts',
  'audit_entries', 'alerts'];

async function assertShape(client, version = 3) {
  const result = await client.query(`SELECT ${tables.map(name => `to_regclass('public.${name}') AS ${name}`).join(', ')},
    to_regclass('public.events_retention_idx') AS retention_index,
    to_regclass('public.provider_credentials') AS provider_credentials`);
  for (const name of tables) if (!result.rows[0][name]) throw new Error('Missing HookLab table: ' + name);
  if (version >= 2 && !result.rows[0].retention_index) throw new Error('Missing HookLab retention index');
  if (version >= 3 && !result.rows[0].provider_credentials) throw new Error('Missing provider credentials table');
  if (version >= 3) {
    const columns = await client.query(`SELECT attrelid::regclass::text AS table_name,attname FROM pg_attribute
      WHERE attrelid IN ('public.events'::regclass,'public.provider_credentials'::regclass)
      AND attnum>0 AND NOT attisdropped`);
    const names = new Set(columns.rows.map(row => row.table_name.replace(/^public\./, '') + '.' + row.attname));
    for (const name of ['events.source', 'events.provider', 'provider_credentials.secret_ciphertext',
      'provider_credentials.previous_secret_ciphertext', 'provider_credentials.previous_expires_at']) {
      if (!names.has(name)) throw new Error('Missing HookLab schema v3 column: ' + name);
    }
  }
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
  if (versions !== null && !(versions.length >= 1 && versions.length <= 3 &&
    versions.every((version, index) => version === index + 1))) {
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
    versions = [1, 2];
  }
  if (versions.at(-1) === 2) {
    await assertShape(client, 2);
    if (!fresh && !allowUpgrade) {
      throw new Error('Schema v2 upgrade requires HOOKLAB_ALLOW_SCHEMA_UPGRADE=1 after a verified backup');
    }
    await client.query('BEGIN');
    try { await runSql(client, sql('migrations/003_provider_ingress.sql')); await client.query('COMMIT'); }
    catch (error) { await client.query('ROLLBACK'); throw error; }
  }
  const final = await schemaVersions(client);
  if (final.join(',') !== '1,2,3') throw new Error('HookLab schema migration did not finish');
  await assertShape(client);
  return latestVersion;
}

module.exports = {schemaVersions, runMigrations, latestVersion};
