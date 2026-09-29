import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

// CI deliberately stops on an upstream installer change until the new
// toolchain has been reviewed and this lock updated. The installer itself is
// still hosted upstream; this is a version gate, not a binary checksum.
export const expected = Object.freeze({
  moon: '0.1.20260920 (914d7da',
  moonc: 'v0.10.14+7d59c7ec9',
});

export function matchesLock(output) {
  return output.split(/\r?\n/).some(line => line.startsWith('moon ' + expected.moon)) &&
    output.split(/\r?\n/).some(line => line.startsWith('moonc ' + expected.moonc));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = spawnSync('moon', ['version', '--all'], {encoding: 'utf8'});
  if (result.error || result.status !== 0 || !matchesLock(result.stdout)) {
    console.error('MoonBit toolchain differs from the reviewed CI versions; inspect moon version --all before updating scripts/check-toolchain-lock.mjs.');
    process.exitCode = 1;
  } else {
    console.log('MoonBit toolchain matches reviewed CI versions.');
  }
}
