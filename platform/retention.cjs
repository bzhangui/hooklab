'use strict';

const {idPattern} = require('./core.cjs');

function policy({tenantId, days, limit = 100, nowMs = Date.now()}) {
  if (typeof tenantId !== 'string' || !idPattern.test(tenantId)) throw new Error('Invalid tenant ID');
  if (!Number.isSafeInteger(days) || days < 30 || days > 3650) throw new Error('Retention days must be 30..3650');
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 500) throw new Error('Batch limit must be 1..500');
  if (!Number.isFinite(nowMs)) throw new Error('Invalid clock');
  return {tenantId, cutoff: new Date(nowMs - days * 86400000).toISOString(), limit};
}

const eligible = `e.tenant_id=$1 AND e.created_at < $2::timestamptz AND NOT EXISTS (
  SELECT 1 FROM deliveries d WHERE d.tenant_id=e.tenant_id AND d.event_id=e.id
  AND (d.state NOT IN ('delivered','dead_lettered') OR d.updated_at >= $2::timestamptz))`;

async function previewRetention(client, settings) {
  const input = policy(settings);
  const tenant = await client.query('SELECT id FROM tenants WHERE id=$1', [input.tenantId]);
  if (!tenant.rowCount) throw new Error('Unknown tenant');
  const result = await client.query(`SELECT count(*)::int AS events FROM events e WHERE ${eligible}`,
    [input.tenantId, input.cutoff]);
  return {mode: 'preview', tenantId: input.tenantId, cutoff: input.cutoff,
    eligibleEvents: result.rows[0].events, maxEventsPerBatch: input.limit};
}

async function applyRetention(client, settings) {
  const input = policy(settings);
  await client.query('BEGIN');
  try {
    const marker = await client.query('SELECT version FROM hooklab_schema ORDER BY version');
    if (marker.rows.map(row => Number(row.version)).join(',') !== '1,2,3') throw new Error('Expected HookLab PostgreSQL schema v3');
    const tenant = await client.query('SELECT id FROM tenants WHERE id=$1 FOR UPDATE', [input.tenantId]);
    if (!tenant.rowCount) throw new Error('Unknown tenant');
    const selection = await client.query(`SELECT e.id FROM events e WHERE ${eligible}
      ORDER BY e.created_at,e.id LIMIT $3 FOR UPDATE OF e SKIP LOCKED`,
    [input.tenantId, input.cutoff, input.limit]);
    const eventIds = selection.rows.map(row => row.id);
    if (!eventIds.length) {
      await client.query('COMMIT');
      return {mode: 'apply', tenantId: input.tenantId, cutoff: input.cutoff, deletedEvents: 0,
        deletedDeliveries: 0, deletedAttempts: 0};
    }
    const locked = await client.query(`SELECT id,state,updated_at FROM deliveries
      WHERE tenant_id=$1 AND event_id=ANY($2::uuid[]) ORDER BY id FOR UPDATE`, [input.tenantId, eventIds]);
    if (locked.rows.some(row => !['delivered','dead_lettered'].includes(row.state) ||
      new Date(row.updated_at).toISOString() >= input.cutoff)) throw new Error('Delivery changed during retention batch');
    const deliveryIds = locked.rows.map(row => row.id);
    const attempts = await client.query(`DELETE FROM delivery_attempts WHERE tenant_id=$1 AND delivery_id=ANY($2::uuid[])`,
      [input.tenantId, deliveryIds]);
    const deliveries = await client.query(`DELETE FROM deliveries WHERE tenant_id=$1 AND id=ANY($2::uuid[])`,
      [input.tenantId, deliveryIds]);
    const events = await client.query(`DELETE FROM events WHERE tenant_id=$1 AND id=ANY($2::uuid[])`,
      [input.tenantId, eventIds]);
    if (events.rowCount !== eventIds.length || deliveries.rowCount !== deliveryIds.length) {
      throw new Error('Retention row count changed; batch rolled back');
    }
    await client.query(`INSERT INTO audit_entries(tenant_id,actor,action,resource) VALUES($1,'retention-cli','events.purged',$2)`,
      [input.tenantId, 'count=' + events.rowCount + ';cutoff=' + input.cutoff]);
    await client.query('COMMIT');
    return {mode: 'apply', tenantId: input.tenantId, cutoff: input.cutoff,
      deletedEvents: events.rowCount, deletedDeliveries: deliveries.rowCount, deletedAttempts: attempts.rowCount};
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  }
}

module.exports = {policy, previewRetention, applyRetention};
