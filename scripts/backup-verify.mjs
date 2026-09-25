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

async function sha256File(file) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}

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
    "SELECT (SELECT max(version) FROM hooklab_schema), (SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename IN ('hooklab_schema','tenants','access_keys','applications','endpoints','subscriptions','event_contracts','events','deliveries','delivery_attempts','audit_entries','alerts')), (SELECT count(*) FROM tenants), (SELECT count(*) FROM events), (SELECT count(*) FROM endpoints), (SELECT count(*) FROM delivery_attempts)"]);
  const fields = result.split('|').map(Number);
  if (fields.length !== 6 || fields[0] !== 1 || fields[1] !== 12 || fields.some(value => !Number.isInteger(value) || value < 0)) {
    throw new Error('Restored database failed schema and count checks');
  }
  const ciphertext = await database(['psql', '-U', 'hooklab', '-d', tempDb, '-At', '-c',
    'SELECT secret_ciphertext FROM endpoints ORDER BY id LIMIT 1']);
  if (fields[4] > 0) {
    const parts = ciphertext.split('.');
    if (parts.length !== 3 || !/^[0-9a-fA-F]{64}$/.test(env.HOOKLAB_ENCRYPTION_KEY || '')) {
      throw new Error('Restored endpoint cannot be checked with the configured encryption key');
    }
    try {
      const [iv, tag, value] = parts.map(part => Buffer.from(part, 'base64url'));
      const decipher = crypto.createDecipheriv('aes-256-gcm', Buffer.from(env.HOOKLAB_ENCRYPTION_KEY, 'hex'), iv);
      decipher.setAuthTag(tag);
      const secret = Buffer.concat([decipher.update(value), decipher.final()]);
      if (secret.length < 16) throw new Error('Restored secret is unexpectedly short');
    } catch (_) { throw new Error('Restored endpoint secret cannot be decrypted with the configured key'); }
  }
  const manifest = {
    format: 'hooklab-backup-v1',
    archive: path.basename(archive),
    createdAt: new Date().toISOString(),
    sha256: await sha256File(archive),
    encryptionKeySha256: crypto.createHash('sha256').update(Buffer.from(env.HOOKLAB_ENCRYPTION_KEY, 'hex')).digest('hex'),
    schemaVersion: fields[0],
    counts: {tenants: fields[2], events: fields[3], endpoints: fields[4], deliveryAttempts: fields[5]},
  };
  fs.writeFileSync(archive + '.manifest.json', JSON.stringify(manifest, null, 2) + '\n',
    {flag: 'wx', mode: 0o600});
  console.log('Backup restored and verified in an isolated temporary database.');
  console.log('Restored tenants: ' + fields[2] + '; events: ' + fields[3] +
    '; endpoints: ' + fields[4] + '; delivery attempts: ' + fields[5] + '.');
  console.log(fields[4] ? 'Restored endpoint secret decrypted with the configured key.' :
    'No endpoint secret exists; key compatibility was not tested.');
  console.log('Private archive: ' + archive);
  console.log('Private manifest: ' + archive + '.manifest.json');
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
