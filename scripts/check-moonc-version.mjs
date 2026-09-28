import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export function parseMooncVersion(output) {
  const match = /^(?:moonc\s+)?v?(\d+)\.(\d+)\.(\d+)\b/m.exec(output.trim());
  if (!match) throw new Error('Could not read moonc version');
  return match.slice(1).map(Number);
}

export function atLeast(actual, minimum) {
  for (let i = 0; i < 3; i++) {
    if (actual[i] !== minimum[i]) return actual[i] > minimum[i];
  }
  return true;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = spawnSync('moonc', ['-v'], {encoding: 'utf8'});
  if (result.error || result.status !== 0) {
    console.error('moonc is unavailable; install MoonBit before running checks.');
    process.exitCode = 1;
  } else {
    try {
      const version = parseMooncVersion(result.stdout + result.stderr);
      if (!atLeast(version, [0, 10, 14])) {
        console.error(`moonc ${version.join('.')} is below required 0.10.14.`);
        process.exitCode = 1;
      } else {
        console.log(`moonc ${version.join('.')} satisfies required >= 0.10.14.`);
      }
    } catch (error) {
      console.error(error.message);
      process.exitCode = 1;
    }
  }
}
