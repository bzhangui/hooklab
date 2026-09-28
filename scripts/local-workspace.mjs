import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {restrictPrivatePath} from './private-path.mjs';

const root = path.resolve(import.meta.dirname, '..');
const privatePath = path.join(root, '.env.portal-local');
const deploymentPath = path.join(root, '.env');

function envValue(source, key) {
  const match = source.match(new RegExp('^' + key + '=([A-Za-z0-9_-]+)$', 'm'));
  if (!match) throw new Error('Missing ' + key + ' in private .env');
  return match[1];
}
async function responseJson(response) {
  const value = await response.json();
  if (!response.ok) throw new Error(value.error || 'HTTP ' + response.status);
  return value;
}

try {
  if (!fs.existsSync(deploymentPath)) throw new Error('Run npm run quickstart first');
  const deployment = fs.readFileSync(deploymentPath, 'utf8');
  const port = Number(envValue(deployment, 'HOOKLAB_PORT'));
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid HOOKLAB_PORT');
  const address = 'http://127.0.0.1:' + port;
  const health = await responseJson(await fetch(address + '/health'));
  if (health.status !== 'ok') throw new Error('HookLab is not healthy');
  if (fs.existsSync(privatePath)) {
    restrictPrivatePath(privatePath);
    const local = fs.readFileSync(privatePath, 'utf8');
    const tenantId = envValue(local, 'HOOKLAB_TENANT_ID');
    const ownerToken = envValue(local, 'HOOKLAB_OWNER_TOKEN');
    await responseJson(await fetch(address + '/api/tenants/' + encodeURIComponent(tenantId) + '/catalog', {
      headers: {authorization: 'Bearer ' + ownerToken},
    }));
    console.log('Existing local workspace is ready: ' + tenantId);
  } else {
    const tenantId = 'local-' + crypto.randomBytes(5).toString('hex');
    const bootstrapToken = envValue(deployment, 'HOOKLAB_BOOTSTRAP_TOKEN');
    const created = await responseJson(await fetch(address + '/api/admin/tenants', {
      method: 'POST',
      headers: {authorization: 'Bearer ' + bootstrapToken, 'content-type': 'application/json'},
      body: JSON.stringify({id: tenantId, name: 'Local workspace'}),
    }));
    if (created.id !== tenantId || !created.ownerToken) throw new Error('Unexpected tenant response');
    const privateFile = fs.openSync(privatePath, 'wx', 0o600);
    let saved = false;
    try {
      restrictPrivatePath(privatePath);
      fs.writeFileSync(privateFile,
        'HOOKLAB_TENANT_ID=' + tenantId + '\nHOOKLAB_OWNER_TOKEN=' + created.ownerToken + '\n');
      saved = true;
    } finally {
      fs.closeSync(privateFile);
      if (!saved) fs.unlinkSync(privatePath);
    }
    console.log('Created local workspace: ' + tenantId);
  }
  console.log('Portal: ' + address + '/');
  console.log('Use the tenant ID and owner token from private ' + privatePath + ' to connect. Never commit or share that file.');
} catch (error) {
  console.error('Local workspace setup failed: ' + error.message);
  process.exitCode = 1;
}
