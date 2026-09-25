import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {pipeline} from 'node:stream/promises';

const root = path.resolve(import.meta.dirname, '..');
const envPath = path.join(root, '.env');
if (!fs.existsSync(envPath)) throw new Error('Run npm run quickstart first; private .env is missing');
const env = {...process.env};
for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
  const match = /^([A-Z_]+)=([A-Za-z0-9_-]+)$/.exec(line);
  if (match) env[match[1]] = match[2];
}
const tempDb = 'hooklab_restore_' + crypto.randomBytes(4).toString('hex');
const backupDir = path.join(root, 'backups');
fs.mkdirSync(backupDir, {recursive: true, mode: 0o700});
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const archive = path.join(backupDir, 'hooklab-' + stamp + '-' + crypto.randomBytes(4).toString('hex') + '.dump');
let created = false;

async function database(args, options = {}) {
  const child = spawn('docker', ['compose', 'exec', '-T', 'database', ...args],
    {cwd: root, env, stdio: ['pipe', 'pipe', 'pipe']});
  let stderr = '';
  let stdout = '';
  child.stderr.on('data', chunk => { if (stderr.length < 8192) stderr += chunk; });
  if (options.output) {
    const output = fs.createWriteStream(options.output, {flags: 'wx', mode: 0o600});
    var transfer = pipeline(child.stdout, output);
  } else {
    child.stdout.on('data', chunk => { if (stdout.length < 8192) stdout += chunk; });
  }
  if (options.input) var feeding = pipeline(fs.createReadStream(options.input), child.stdin);
  else child.stdin.end();
  const code = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', resolve);
  });
  if (transfer) await transfer;
  if (feeding) await feeding;
  if (code !== 0) throw new Error('PostgreSQL command failed: ' + stderr.trim());
  return stdout.trim();
}

try {
  await database(['pg_dump', '-U', 'hooklab', '-d', 'hooklab', '-Fc', '--no-owner', '--no-acl'], {output: archive});
  if (fs.statSync(archive).size < 1024) throw new Error('Backup archive is unexpectedly small');
  await database(['createdb', '-U', 'hooklab', tempDb]);
  created = true;
  await database(['pg_restore', '-U', 'hooklab', '-d', tempDb, '--exit-on-error', '--no-owner', '--no-acl'], {input: archive});
  const result = await database(['psql', '-U', 'hooklab', '-d', tempDb, '-At', '-c',
    "SELECT (SELECT max(version) FROM hooklab_schema), (SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename IN ('tenants','events','deliveries','delivery_attempts')), (SELECT count(*) FROM tenants), (SELECT count(*) FROM events)"]);
  const fields = result.split('|').map(Number);
  if (fields.length !== 4 || fields[0] !== 1 || fields[1] !== 4 || fields.some(value => !Number.isInteger(value) || value < 0)) {
    throw new Error('Restored database failed schema and count checks');
  }
  console.log('Backup restored and verified in an isolated temporary database.');
  console.log('Restored tenants: ' + fields[2] + '; events: ' + fields[3] + '.');
  console.log('Private archive: ' + archive);
  console.log('Back up HOOKLAB_ENCRYPTION_KEY separately; it is not inside the database archive.');
} catch (error) {
  if (fs.existsSync(archive) && fs.statSync(archive).size === 0) fs.rmSync(archive);
  throw error;
} finally {
  if (created) {
    try { await database(['dropdb', '-U', 'hooklab', tempDb]); }
    catch (error) { console.error('Temporary restore database remains: ' + tempDb + '. ' + error.message); }
  }
}
