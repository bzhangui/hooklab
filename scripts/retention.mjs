import pg from 'pg';
import {policy, previewRetention, applyRetention} from '../platform/retention.cjs';

function args(argv) {
  const values = {};
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i];
    if (key === '--apply') {
      if (values.apply) throw new Error('Duplicate --apply');
      values.apply = true;
    } else if (['--tenant', '--days', '--limit', '--confirm-tenant'].includes(key)) {
      if (values[key] !== undefined || !argv[i + 1]) throw new Error('Missing or duplicate ' + key);
      values[key] = argv[++i];
    } else throw new Error('Unknown argument: ' + key);
  }
  if (!values['--tenant'] || !values['--days']) throw new Error('Required: --tenant ID --days 30..3650');
  if (values.apply && values['--confirm-tenant'] !== values['--tenant']) {
    throw new Error('Apply requires --confirm-tenant with the same tenant ID');
  }
  if (!values.apply && values['--confirm-tenant']) throw new Error('--confirm-tenant requires --apply');
  return {tenantId: values['--tenant'], days: Number(values['--days']),
    limit: values['--limit'] === undefined ? 100 : Number(values['--limit']), apply: Boolean(values.apply)};
}

const settings = args(process.argv.slice(2));
policy(settings);
if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is required');
const client = new pg.Client({connectionString: process.env.DATABASE_URL, connectionTimeoutMillis: 5000});
try {
  await client.connect();
  const result = settings.apply ? await applyRetention(client, settings) : await previewRetention(client, settings);
  console.log(JSON.stringify(result, null, 2));
} finally { await client.end(); }
