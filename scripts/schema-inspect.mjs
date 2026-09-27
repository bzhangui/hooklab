import pg from 'pg';
import {schemaVersions, latestVersion} from '../platform/migrations.cjs';

if (process.argv.length !== 2) throw new Error('Usage: npm run schema:inspect');
if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is required');
const client = new pg.Client({connectionString: process.env.DATABASE_URL, connectionTimeoutMillis: 5000});
try {
  await client.connect();
  const versions = await schemaVersions(client);
  const state = versions === null ? 'uninitialized' : versions.join(',') === '1' ? 'upgrade_required' :
    versions.join(',') === '1,2' ? 'current' : 'unsupported';
  console.log(JSON.stringify({state, versions: versions || [], supportedVersion: latestVersion}, null, 2));
  if (state === 'unsupported') process.exitCode = 1;
} finally { await client.end(); }
