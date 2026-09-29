import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const withPlatform = process.argv.slice(2).includes('--platform');
if (process.argv.slice(2).some(arg => arg !== '--platform')) {
  console.error('Usage: node scripts/reviewer-smoke.mjs [--platform]');
  process.exit(2);
}

function run(label, command, args) {
  console.log(`\n[reviewer] ${label}`);
  const result = spawnSync(command, args, {cwd: root, stdio: 'inherit', shell: false});
  if (result.error || result.status !== 0) {
    throw new Error(`${label} failed (${result.error?.message || result.status})`);
  }
}

try {
  run('required compiler version', process.execPath, ['scripts/check-moonc-version.mjs']);
  run('published package business API', process.execPath, ['scripts/mooncakes-smoke.mjs']);
  run('MoonBit format', 'moon', ['fmt', '--check']);
  run('MoonBit four-target check', 'moon', ['check', '--target', 'all', '--deny-warn']);
  run('MoonBit four-target tests', 'moon', ['test', '--target', 'all', '--deny-warn']);
  run('MoonBit four-target build', 'moon', ['build', '--target', 'all', '--deny-warn']);
  if (process.platform === 'win32') {
    run('synthetic CLI flow', 'powershell.exe', ['-NoProfile', '-File', 'scripts/demo.ps1']);
  } else {
    run('synthetic CLI flow', 'bash', ['scripts/demo.sh']);
  }
  if (withPlatform) {
    run('install locked Node dependencies', process.platform === 'win32' ? 'npm.cmd' : 'npm', ['ci', '--ignore-scripts']);
    run('platform helper coverage', process.platform === 'win32' ? 'npm.cmd' : 'npm', ['run', 'test:platform:coverage']);
    run('disposable PostgreSQL multi-persona flow', process.execPath, ['scripts/simulated-pilot-local.mjs', '--repeat', '1']);
  }
  console.log('\nReviewer smoke passed. This uses synthetic data; it is not an external-user pilot.');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
