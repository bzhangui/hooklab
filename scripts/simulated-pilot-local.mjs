import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {dockerCommand, dockerEnvironment} from './docker-cli.mjs';
import {parseOptions} from './simulated-pilot.mjs';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const dockerExecutable = dockerCommand();
const dockerEnv = dockerEnvironment(dockerExecutable);

function docker(args) {
  const result = spawnSync(dockerExecutable, args, {cwd: root, env: dockerEnv, encoding: 'utf8',
    maxBuffer: 2 * 1024 * 1024});
  if (result.error || result.status !== 0) {
    throw new Error(`Disposable Docker operation failed (${args[0]}): ${result.stderr || result.error?.message || result.status}`);
  }
  return result.stdout.trim();
}

export function publishedPort(output) {
  const match = /^127\.0\.0\.1:(\d{1,5})$/m.exec(output);
  const port = Number(match?.[1]);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Missing loopback-only PostgreSQL port');
  return port;
}

async function main() {
  const options = parseOptions(['--profile', 'full', ...process.argv.slice(2)]);
  const name = 'hooklab-sim-pg-' + crypto.randomBytes(6).toString('hex');
  const password = crypto.randomBytes(24).toString('hex');
  let id;
  try {
    id = docker(['run', '--rm', '-d', '--name', name,
      '-e', 'POSTGRES_USER=postgres', '-e', `POSTGRES_PASSWORD=${password}`,
      '-e', 'POSTGRES_DB=hooklab_test', '-p', '127.0.0.1::5432', 'postgres:17']);
    if (!/^[0-9a-f]{64}$/.test(id)) throw new Error('Docker did not return the disposable container ID');
    const port = publishedPort(docker(['port', id, '5432/tcp']));
    let ready = false;
    for (let i = 0; i < 60; i++) {
      const check = spawnSync(dockerExecutable, ['exec', id, 'pg_isready', '-U', 'postgres', '-d', 'hooklab_test'],
        {cwd: root, env: dockerEnv, stdio: 'ignore'});
      if (check.status === 0) { ready = true; break; }
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    if (!ready) throw new Error('Disposable PostgreSQL did not become ready');
    console.log('Running synthetic personas against a disposable loopback PostgreSQL container.');
    const result = spawnSync(process.execPath,
      [resolve(root, 'scripts', 'simulated-pilot.mjs'), '--profile', 'full', '--repeat', String(options.repeat)],
      {cwd: root, env: {...process.env,
        TEST_DATABASE_URL: `postgresql://postgres:${password}@127.0.0.1:${port}/hooklab_test`},
      stdio: 'inherit'});
    if (result.error || result.status !== 0) throw new Error('Synthetic pilot failed; inspect the private target report');
  } finally {
    if (id && /^[0-9a-f]{64}$/.test(id)) {
      docker(['stop', id]); // --rm removes only the container created above; no volumes or user service.
    }
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
