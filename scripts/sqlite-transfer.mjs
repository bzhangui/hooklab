import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import pg from 'pg';
import {schemaVersions} from '../platform/migrations.cjs';
import {idPattern, eventTypePattern} from '../platform/core.cjs';

const format = 'hooklab-sqlite-history-v1';
const terminal = new Set(['delivered', 'dead_lettered', 'cancelled']);
const providers = new Set(['github', 'stripe', 'feishu', 'generic-hmac']);
const digest = value => crypto.createHash('sha256').update(value).digest('hex');

function exportHistory(sqlitePath) {
  const db = new DatabaseSync(sqlitePath, {readOnly: true});
  try {
    db.exec('PRAGMA query_only=ON; BEGIN');
    const version = db.prepare("SELECT value FROM metadata WHERE key='schema_version'").get();
    if (!version || version.value !== '1') throw new Error('Unsupported SQLite gateway schema');
    const unfinished = db.prepare(`SELECT count(*) AS total FROM deliveries
      WHERE state NOT IN ('delivered','dead_lettered','cancelled')`).get().total;
    if (unfinished) throw new Error(`Refusing history export: ${unfinished} non-terminal deliveries remain`);
    const records = db.prepare(`SELECT id,source,provider,event_type,body,received_at FROM events
      ORDER BY received_at,id`).all();
    if (records.length > 10000) throw new Error('History transfer is capped at 10,000 events per archive');
    const summary = db.prepare('SELECT state,count(*) AS total FROM deliveries GROUP BY state').all();
    db.exec('COMMIT');
    const payload = {records, summary};
    return {format, checksum: digest(JSON.stringify(payload)), payload};
  } catch (error) { try { db.exec('ROLLBACK'); } catch (_) {} throw error; }
  finally { db.close(); }
}

function validateBundle(bundle) {
  if (!bundle || bundle.format !== format || !bundle.payload ||
    !Array.isArray(bundle.payload.records) || !Array.isArray(bundle.payload.summary) ||
    bundle.payload.records.length > 10000 || bundle.checksum !== digest(JSON.stringify(bundle.payload))) {
    throw new Error('Invalid or modified HookLab transfer archive');
  }
  const seen = new Set();
  for (const row of bundle.payload.records) {
    if (!row || typeof row.id !== 'string' || !row.id || seen.has(row.id) ||
      !['ingress','outbound'].includes(row.source) || !eventTypePattern.test(row.event_type) ||
      typeof row.body !== 'string' || !Number.isSafeInteger(row.received_at) ||
      row.received_at < 0 || row.received_at > 8640000000000000 ||
      row.source === 'ingress' && !providers.has(row.provider)) throw new Error('Invalid event in transfer archive');
    seen.add(row.id);
  }
  if (bundle.payload.summary.some(row => !terminal.has(row.state) ||
    !Number.isSafeInteger(row.total) || row.total < 0)) throw new Error('Archive contains non-terminal delivery state');
  return bundle.payload;
}

async function importHistory(client, bundle, {tenantId, applicationId, apply = false} = {}) {
  const payload = validateBundle(bundle);
  if (!idPattern.test(tenantId) || !idPattern.test(applicationId)) throw new Error('Invalid target tenant or application ID');
  const versions = await schemaVersions(client);
  if (!versions || versions.join(',') !== '1,2,3') throw new Error('Target must use HookLab PostgreSQL schema v3');
  await client.query('BEGIN');
  try {
    const app = await client.query(`SELECT id FROM applications WHERE tenant_id=$1 AND id=$2 FOR UPDATE`,
      [tenantId, applicationId]);
    if (!app.rowCount) throw new Error('Target application not found');
    let newEvents = 0, existingEvents = 0;
    for (const row of payload.records) {
      const key = 'history:' + digest(row.source + '\n' + row.id);
      const source = row.source === 'ingress' ? 'provider' : 'application';
      const provider = source === 'provider' ? row.provider : null;
      const fingerprint = digest('application/json\n' + row.event_type + '\n' + row.body);
      const prior = await client.query(`SELECT fingerprint,source,provider FROM events
        WHERE tenant_id=$1 AND application_id=$2 AND idempotency_key=$3`, [tenantId, applicationId, key]);
      if (prior.rowCount) {
        if (prior.rows[0].fingerprint !== fingerprint || prior.rows[0].source !== source || prior.rows[0].provider !== provider) {
          throw new Error('Import key conflict; target database was not changed');
        }
        existingEvents++;
      } else {
        newEvents++;
        if (apply) await client.query(`INSERT INTO events
          (id,tenant_id,application_id,event_type,idempotency_key,fingerprint,body,content_type,trace_id,created_at,source,provider)
          VALUES($1,$2,$3,$4,$5,$6,$7,'application/json',$8,$9,$10,$11)`,
        [crypto.randomUUID(), tenantId, applicationId, row.event_type, key, fingerprint, row.body,
          digest(row.id).slice(0, 32), new Date(row.received_at).toISOString(), source, provider]);
      }
    }
    if (apply) await client.query(`INSERT INTO audit_entries(tenant_id,actor,action,resource)
      VALUES($1,'sqlite-transfer','history.imported',$2)`, [tenantId, `application=${applicationId};new=${newEvents}`]);
    await client.query(apply ? 'COMMIT' : 'ROLLBACK');
    return {mode: apply ? 'apply' : 'preview', tenantId, applicationId,
      archiveEvents: payload.records.length, newEvents, existingEvents,
      importedDeliveries: 0, note: 'Historical events only; no queue, endpoint, secret or delivery attempt is imported.'};
  } catch (error) { await client.query('ROLLBACK'); throw error; }
}

async function main(args) {
  const [action, ...rest] = args;
  const option = name => { const index = rest.indexOf(name); return index < 0 ? undefined : rest[index + 1]; };
  if (action === 'export') {
    const sqlite = option('--sqlite'), output = option('--out');
    if (!sqlite || !output || !output.endsWith('.hooklab-transfer.json')) throw new Error('Usage: export --sqlite PATH --out PATH.hooklab-transfer.json');
    const bundle = exportHistory(sqlite);
    fs.writeFileSync(output, JSON.stringify(bundle), {flag: 'wx', mode: 0o600});
    console.log(JSON.stringify({mode: 'export', archive: path.resolve(output), events: bundle.payload.records.length,
      deliveryStates: bundle.payload.summary, warning: 'Archive contains raw event bodies; keep private.'}));
    return;
  }
  if (action === 'import') {
    const file = option('--file'), tenantId = option('--tenant'), applicationId = option('--app');
    if (!file || !tenantId || !applicationId || !process.env.DATABASE_URL) throw new Error('Usage: import --file ARCHIVE --tenant ID --app ID [--apply --confirm-tenant ID --confirm-app ID] with DATABASE_URL');
    const apply = rest.includes('--apply');
    if (apply && (option('--confirm-tenant') !== tenantId || option('--confirm-app') !== applicationId)) {
      throw new Error('Apply requires matching tenant and application confirmations');
    }
    if (fs.statSync(file).size > 100 * 1024 * 1024) throw new Error('Transfer archive exceeds 100 MiB');
    const bundle = JSON.parse(fs.readFileSync(file, 'utf8'));
    const client = new pg.Client({connectionString: process.env.DATABASE_URL, connectionTimeoutMillis: 5000});
    try { await client.connect(); console.log(JSON.stringify(await importHistory(client, bundle, {tenantId, applicationId, apply}))); }
    finally { await client.end(); }
    return;
  }
  throw new Error('Usage: export --sqlite PATH --out PATH.hooklab-transfer.json | import --file ARCHIVE --tenant ID --app ID [--apply --confirm-tenant ID --confirm-app ID]');
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).catch(error => { console.error(error.message); process.exitCode = 1; });
}

export {exportHistory, validateBundle, importHistory};
