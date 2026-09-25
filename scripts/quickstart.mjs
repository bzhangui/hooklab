import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const envPath = path.join(root, '.env');
const docker = spawnSync('docker', ['compose', 'version'], {cwd: root, stdio: 'ignore'});
if (docker.status !== 0) {
  console.error('Docker Compose is required. No files were changed.');
  process.exit(1);
}

function parseEnv(value) {
  const result = {};
  for (const line of value.split(/\r?\n/)) {
    if (!line || line.startsWith('#')) continue;
    const match = /^([A-Z_]+)=(.*)$/.exec(line);
    if (!match || Object.hasOwn(result, match[1])) throw new Error('Invalid or duplicate .env entry');
    result[match[1]] = match[2];
  }
  return result;
}
function validateEnv(env) {
  for (const key of ['HOOKLAB_DB_PASSWORD', 'HOOKLAB_BOOTSTRAP_TOKEN', 'HOOKLAB_METRICS_TOKEN']) {
    if (!/^[A-Za-z0-9_-]{32,}$/.test(env[key] || '')) throw new Error('Invalid ' + key + ' in private .env');
  }
  if (!/^[0-9a-fA-F]{64}$/.test(env.HOOKLAB_ENCRYPTION_KEY || '')) throw new Error('Invalid HOOKLAB_ENCRYPTION_KEY in private .env');
  const port = Number(env.HOOKLAB_PORT || '8787');
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid HOOKLAB_PORT in private .env');
  return port;
}

let env;
if (fs.existsSync(envPath)) {
  env = parseEnv(fs.readFileSync(envPath, 'utf8'));
} else {
  env = {
    HOOKLAB_DB_PASSWORD: crypto.randomBytes(32).toString('base64url'),
    HOOKLAB_ENCRYPTION_KEY: crypto.randomBytes(32).toString('hex'),
    HOOKLAB_BOOTSTRAP_TOKEN: crypto.randomBytes(32).toString('base64url'),
    HOOKLAB_METRICS_TOKEN: crypto.randomBytes(32).toString('base64url'),
    HOOKLAB_PORT: '8787',
  };
  fs.writeFileSync(envPath, Object.entries(env).map(([key, value]) => key + '=' + value).join('\n') + '\n',
    {flag: 'wx', mode: 0o600});
  console.log('Created private .env. Keep it out of Git and back up the encryption key securely.');
}
const port = validateEnv(env);
const compose = spawnSync('docker', ['compose', 'up', '--build', '-d'],
  {cwd: root, stdio: 'inherit', env: {...process.env, ...env}});
if (compose.status !== 0) process.exit(compose.status || 1);

let healthy = false;
for (let i = 0; i < 90; i++) {
  try {
    const response = await fetch('http://127.0.0.1:' + port + '/health');
    if (response.ok && (await response.json()).status === 'ok') { healthy = true; break; }
  } catch (_) {}
  await new Promise(resolve => setTimeout(resolve, 1000));
}
if (!healthy) {
  console.error('Containers started, but HookLab health did not become ready. Inspect docker compose logs.');
  process.exit(1);
}
console.log('HookLab is ready at http://127.0.0.1:' + port + '/');
console.log('Bootstrap and metrics tokens are in the private .env file; they were not printed.');
