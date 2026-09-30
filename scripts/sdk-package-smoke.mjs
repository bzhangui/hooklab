import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
import {existsSync, mkdtempSync, mkdirSync, readFileSync, realpathSync, rmSync} from 'node:fs';
import {dirname, join, resolve, sep} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const sdk = join(root, 'sdk', 'node');
const npmCli = [process.env.npm_execpath,
  join(dirname(process.execPath), 'node_modules', 'npm', 'bin', 'npm-cli.js'),
  join(dirname(process.execPath), '..', 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js')]
  .find(candidate => candidate && existsSync(candidate));
if (!npmCli) throw new Error('Cannot locate npm CLI alongside Node.js');

function run(args, cwd) {
  const result = spawnSync(process.execPath, [npmCli, ...args], {cwd, encoding: 'utf8',
    timeout: 120000, maxBuffer: 2 * 1024 * 1024});
  if (result.error || result.status !== 0) {
    throw new Error(`npm ${args[0]} failed: ${result.stderr || result.error?.message || result.stdout}`);
  }
  return result.stdout;
}

const temp = mkdtempSync(join(tmpdir(), 'hooklab-sdk-'));
try {
  const metadata = JSON.parse(run(['pack', sdk, '--offline', '--json', '--pack-destination', temp], root));
  assert.equal(metadata.length, 1);
  const entry = metadata[0];
  assert.equal(entry.name, '@bzhangui/hooklab-receiver');
  assert.deepEqual(entry.files.map(file => file.path).sort(),
    ['LICENSE', 'README.md', 'package.json', 'receiver.cjs']);
  const archive = join(temp, entry.filename);
  const project = join(temp, 'consumer');
  mkdirSync(project);
  run(['install', '--offline', '--ignore-scripts', '--no-audit', '--no-fund',
    '--package-lock=false', '--prefix', project, archive], root);
  const installed = createRequire(join(project, 'smoke.cjs'))('@bzhangui/hooklab-receiver');
  const body = Buffer.from('{"message":"hello\\nHookLab"}', 'utf8');
  const headers = {
    'x-hooklab-timestamp': '1700000000',
    'x-hooklab-delivery-id': 'delivery:demo',
    'x-hooklab-event-id': 'publish:demo',
    'x-hooklab-event-type': 'order.created',
    'x-hooklab-key-id': 'key-v1',
    'x-hooklab-signature': 'v1=978a6161dd2b90f1a4576d6982447e4e45c0fea27ec2a414fcf3c487549172e0',
  };
  const options = {headers, body, secrets: {'key-v1': 'test-secret'}, nowMs: 1700000000000};
  assert.equal(installed.verifyDelivery(options).ok, true);
  assert.equal(installed.verifyDelivery({...options, body: Buffer.from('{}')}).code, 'invalid_signature');
  assert.equal(installed.verifyDelivery({...options, nowMs: options.nowMs + 301000}).code, 'stale_timestamp');
  assert.equal(installed.verifyDelivery({...options, secrets: {}}).code, 'unknown_key');
  assert.equal(readFileSync(join(project, 'node_modules', '@bzhangui', 'hooklab-receiver', 'LICENSE'), 'utf8'),
    readFileSync(join(root, 'LICENSE'), 'utf8'));
  assert.equal('v1=' + crypto.createHmac('sha256', 'test-secret')
    .update('v1\n1700000000\ndelivery:demo\npublish:demo\norder.created\n').update(body).digest('hex'),
  headers['x-hooklab-signature']);
  console.log('Node receiver package: offline pack/install, allowlisted contents, license and signature checks passed.');
} finally {
  const base = realpathSync(tmpdir());
  const exact = realpathSync(temp);
  if (!exact.startsWith(base + sep)) throw new Error('Refusing to remove a path outside the temporary directory');
  rmSync(exact, {recursive: true, force: true});
}
