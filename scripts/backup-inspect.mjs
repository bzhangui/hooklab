import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
if (process.argv.length !== 3) {
  console.error('Usage: npm run backup:inspect -- <archive.dump>');
  process.exit(2);
}
const archive = path.resolve(process.argv[2]);
const manifestPath = archive + '.manifest.json';
const envPath = path.join(root, '.env');
if (!fs.existsSync(archive) || !fs.existsSync(manifestPath) || !fs.existsSync(envPath)) {
  throw new Error('Archive, adjacent manifest and private .env must all be available');
}
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
if (manifest.format !== 'hooklab-backup-v1' || manifest.archive !== path.basename(archive) ||
  !/^[0-9a-f]{64}$/.test(manifest.sha256) || !/^[0-9a-f]{64}$/.test(manifest.encryptionKeySha256)) {
  throw new Error('Backup manifest is invalid');
}
const hash = crypto.createHash('sha256');
for await (const chunk of fs.createReadStream(archive)) hash.update(chunk);
if (hash.digest('hex') !== manifest.sha256) throw new Error('Backup archive checksum does not match manifest');
const key = /^HOOKLAB_ENCRYPTION_KEY=([0-9a-fA-F]{64})\r?$/m.exec(fs.readFileSync(envPath, 'utf8'))?.[1];
if (!key || crypto.createHash('sha256').update(Buffer.from(key, 'hex')).digest('hex') !== manifest.encryptionKeySha256) {
  throw new Error('Private encryption key does not match backup manifest');
}
console.log('Archive checksum and encryption-key fingerprint match the private manifest.');
console.log('This offline check does not replace a database restore drill.');
