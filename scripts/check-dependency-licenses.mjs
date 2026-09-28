import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const lockPath = fileURLToPath(new URL('../package-lock.json', import.meta.url));
const allowed = new Set(['MIT', 'ISC', 'Apache-2.0']);

export function checkDependencyLicenses(lock) {
  if (!lock?.packages || typeof lock.packages !== 'object') {
    throw new Error('Missing npm lockfile package inventory');
  }
  const inventory = Object.entries(lock.packages).filter(([path]) => path !== '');
  if (inventory.length === 0) throw new Error('npm lockfile has no dependency inventory');
  const found = new Set();
  for (const [path, metadata] of inventory) {
    if (!allowed.has(metadata?.license)) {
      throw new Error(`${path}: missing or unreviewed license ${metadata?.license ?? '(none)'}`);
    }
    found.add(metadata.license);
  }
  return {count: inventory.length, licenses: [...found].sort()};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const summary = checkDependencyLicenses(JSON.parse(readFileSync(lockPath, 'utf8')));
  console.log(`${summary.count} locked npm packages have reviewed license metadata: ${summary.licenses.join(', ')}`);
}
