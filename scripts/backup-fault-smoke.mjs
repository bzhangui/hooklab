import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
if (process.argv.length !== 3 || !process.env.CI || process.env.CI !== 'true') {
  throw new Error('Usage (disposable CI only): node scripts/backup-fault-smoke.mjs <archive.dump>');
}
const source = path.resolve(process.argv[2]);
const sourceManifest = JSON.parse(fs.readFileSync(source + '.manifest.json', 'utf8'));
const temp = fs.mkdtempSync(path.join(tmpdir(), 'hooklab-backup-fault-'));
const archive = path.join(temp, 'synthetic.dump');
const manifestPath = archive + '.manifest.json';
function inspect(expectedSuccess, reason) {
  const result = spawnSync(process.execPath, [path.join(root, 'scripts', 'backup-inspect.mjs'), archive],
    {cwd: root, encoding: 'utf8', timeout: 30000});
  assert.equal(result.error, undefined);
  assert.equal(result.status === 0, expectedSuccess, reason);
  if (!expectedSuccess) assert.match(result.stderr, /manifest|checksum|encryption key/i, reason);
}
try {
  fs.copyFileSync(source, archive);
  const manifest = {...sourceManifest, archive: path.basename(archive)};
  fs.writeFileSync(manifestPath, JSON.stringify(manifest), {flag: 'wx', mode: 0o600});
  inspect(true, 'The untampered synthetic archive must be accepted');
  fs.writeFileSync(manifestPath, JSON.stringify({...manifest, encryptionKeySha256: '0'.repeat(64)}));
  inspect(false, 'A mismatched private encryption key must be rejected');
  fs.writeFileSync(manifestPath, JSON.stringify(manifest));
  const descriptor = fs.openSync(archive, 'r+');
  try {
    const original = Buffer.alloc(1);
    fs.readSync(descriptor, original, 0, 1, 0);
    fs.writeSync(descriptor, Buffer.from([original[0] ^ 0xff]), 0, 1, 0);
  } finally { fs.closeSync(descriptor); }
  inspect(false, 'A corrupted archive must be rejected before restore');
  // The fixture contains no real external-user data; report only outcomes.
  console.log('Synthetic backup fault drill: intact archive accepted; wrong key and corruption rejected.');
} finally {
  const base = fs.realpathSync(tmpdir());
  const exact = fs.realpathSync(temp);
  if (!exact.startsWith(base + path.sep)) throw new Error('Refusing to remove a path outside the temporary directory');
  fs.rmSync(exact, {recursive: true, force: true});
}
