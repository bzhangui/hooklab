import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export function verifyPackageList(output) {
  const files = output.split(/\r?\n/).map(line => line.trim().replaceAll('\\', '/'));
  for (const required of ['moon.mod', 'README.md', 'LICENSE', 'hooklab/core/types.mbt']) {
    if (!files.includes(required)) throw new Error(`Publish archive is missing ${required}`);
  }
  for (const path of files) {
    if (path === '项目申报书.md' || path.startsWith('backups/') ||
        path.split('/').some(part => part === 'node_modules' || /\.(dump|bak|backup)$/i.test(part)) ||
        path.split('/').some(part => /^\.env(?:\.(?!example$).+)?$/i.test(part))) {
      throw new Error(`Private file would enter Mooncakes archive: ${path}`);
    }
  }
  return files.length;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = spawnSync('moon', ['package', '--list', '--frozen'], {encoding: 'utf8'});
  if (result.error || result.status !== 0) {
    console.error(result.stderr || result.error?.message || 'moon package failed');
    process.exitCode = 1;
  } else {
    try {
      const count = verifyPackageList(result.stdout + result.stderr);
      console.log(`Mooncakes archive checked (${count} listed entries; private paths excluded).`);
    } catch (error) {
      console.error(error.message);
      process.exitCode = 1;
    }
  }
}
