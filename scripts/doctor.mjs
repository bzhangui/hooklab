import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {dockerCommand, dockerEnvironment} from './docker-cli.mjs';

const root = path.resolve(import.meta.dirname, '..');

export function parseLocalPort(contents) {
  const entries = contents.split(/\r?\n/).filter(line => /^HOOKLAB_PORT=/.test(line));
  if (entries.length > 1) throw new Error('duplicate HOOKLAB_PORT');
  if (!entries.length) return 8787;
  const port = Number(entries[0].slice('HOOKLAB_PORT='.length));
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('invalid HOOKLAB_PORT');
  return port;
}

export function healthStatus(httpStatus, body) {
  if (httpStatus !== 200) return {ok: false, detail: '健康接口返回 HTTP ' + httpStatus};
  try {
    return JSON.parse(body).status === 'ok'
      ? {ok: true, detail: '应用与数据库已就绪'}
      : {ok: false, detail: '健康接口未报告就绪'};
  } catch (_) {
    return {ok: false, detail: '健康接口返回非 JSON 正文'};
  }
}

function command(executable, args, options = {}) {
  const result = spawnSync(executable, args, {cwd: root, encoding: 'utf8', timeout: 10000,
    env: options.env || process.env, windowsHide: true});
  return result.status === 0;
}

export async function diagnose() {
  const checks = [];
  const nodeMajor = Number(process.versions.node.split('.')[0]);
  checks.push({name: 'Node.js 24+', ok: nodeMajor >= 24, detail: process.version});
  const moon = command('moon', ['version', '--all']);
  checks.push({name: 'MoonBit CLI', ok: moon,
    detail: moon ? '命令可用' : '缺失时按 MoonBit 官方安装说明安装，之后运行 moon version --all'});
  const docker = dockerCommand();
  const dockerEnv = dockerEnvironment(docker);
  const compose = command(docker, ['compose', 'version'], {env: dockerEnv});
  checks.push({name: 'Docker Compose v2', ok: compose,
    detail: compose ? '命令可用' : '安装并启动 Docker Desktop，再检查 docker compose version'});
  const engine = compose && command(docker, ['info', '--format', '{{.ServerVersion}}'], {env: dockerEnv});
  checks.push({name: 'Docker 引擎', ok: engine,
    detail: engine ? '正在运行' : '启动 Docker Desktop 的 Linux 容器引擎'});
  let port;
  try {
    const envPath = path.join(root, '.env');
    port = fs.existsSync(envPath) ? parseLocalPort(fs.readFileSync(envPath, 'utf8')) : 8787;
  } catch (error) {
    checks.push({name: '本机端口配置', ok: false, detail: error.message});
    return checks;
  }
  try {
    const response = await fetch('http://127.0.0.1:' + port + '/health',
      {signal: AbortSignal.timeout(2500)});
    const status = healthStatus(response.status, await response.text());
    checks.push({name: '本机服务', ok: status.ok, detail: status.detail + ' · 127.0.0.1:' + port});
  } catch (_) {
    checks.push({name: '本机服务', ok: false,
      detail: '127.0.0.1:' + port + ' 未响应；从仓库根目录运行 npm run quickstart'});
  }
  return checks;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const checks = await diagnose();
  if (process.argv.includes('--json')) console.log(JSON.stringify({checks}, null, 2));
  else {
    for (const check of checks) console.log((check.ok ? 'OK  ' : '待处理 ') + check.name + '：' + check.detail);
    console.log('本机服务检查不代表公网部署或真实外部试点。不会显示令牌或密钥。');
  }
  if (checks.some(check => !check.ok)) process.exitCode = 1;
}
