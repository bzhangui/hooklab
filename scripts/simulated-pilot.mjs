import {spawnSync} from 'node:child_process';
import {mkdirSync, readdirSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const reportPath = join(root, 'target', 'simulated-pilot-report.json');
const gatewayScenarios = [
  ['provider', '验签提供方与拒绝伪造请求', 'gateway-e2e.mjs'],
  ['integrator', '配置校验与安全启动', 'gateway-config-e2e.mjs'],
  ['operator', '死信与人工恢复', 'gateway-deadletter-e2e.mjs'],
  ['receiver', '慢接收端与投递隔离', 'gateway-limits-e2e.mjs'],
  ['operator', '熔断与恢复', 'gateway-circuit-e2e.mjs'],
  ['operator', '崩溃后恢复', 'gateway-restart-e2e.mjs'],
  ['publisher', '事件发布与出站投递', 'gateway-outbound-e2e.mjs'],
  ['operator', '租约竞争与接管', 'gateway-lease-e2e.mjs'],
];
const databaseScenarios = [
  ['tenant-owner', '租户隔离、角色权限、契约、重试和密钥轮换', 'platform-e2e.mjs'],
  ['platform-operator', '跨实例额度与积压保护', 'platform-quota-e2e.mjs'],
  ['receiver-operator', '故障接管与合成批量延迟', 'platform-showcase.mjs'],
];

export function validateTestDatabase(value) {
  if (!value) throw new Error('Full simulation requires TEST_DATABASE_URL');
  let url;
  try { url = new URL(value); } catch (_) { throw new Error('Invalid TEST_DATABASE_URL'); }
  if (!['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
      !/^\/hooklab_test(?:_[a-z0-9]+)?$/.test(url.pathname)) {
    throw new Error('Use a dedicated local hooklab_test database; production or remote URLs are refused');
  }
  return true;
}

export function parseOptions(args) {
  if (args.length % 2 !== 0 || args.some((value, index) => index % 2 === 0 &&
      !['--profile', '--repeat'].includes(value)) ||
      args.filter(value => value === '--profile').length > 1 ||
      args.filter(value => value === '--repeat').length > 1) {
    throw new Error('Usage: node scripts/simulated-pilot.mjs --profile quick|full [--repeat 1..30]');
  }
  const profileIndex = args.indexOf('--profile');
  const repeatIndex = args.indexOf('--repeat');
  const profile = profileIndex < 0 ? 'quick' : args[profileIndex + 1];
  const repeatText = repeatIndex < 0 ? '1' : args[repeatIndex + 1];
  if (!['quick', 'full'].includes(profile) || !/^[1-9][0-9]*$/.test(repeatText)) {
    throw new Error('Usage: node scripts/simulated-pilot.mjs --profile quick|full [--repeat 1..30]');
  }
  const repeat = Number(repeatText);
  if (repeat > 30 || (profile === 'quick' && repeat !== 1)) {
    throw new Error('Repeat 1..30 is available only for the full local-database profile');
  }
  return {profile, repeat};
}

export function parseShowcaseSummary(output) {
  const value = JSON.parse(output.trim());
  if (value.scenario !== 'synthetic_loopback_order_delivery' ||
      value.contract_rejection_without_persistence !== true ||
      value.failover?.same_delivery_id !== true ||
      value.failover?.receiver_signatures_verified !== true ||
      value.failover?.deduplicated_consumer_ids !== 1 ||
      value.failover?.final_state !== 'delivered') throw new Error('Incomplete synthetic failover evidence');
  const fields = ['events', 'publish_batch_ms', 'publish_p50_ms', 'publish_p95_ms', 'all_delivered_ms'];
  const sample = {};
  for (const field of fields) {
    const number = value.local_sample?.[field];
    if (!Number.isFinite(number) || number < 0) throw new Error('Invalid synthetic sample ' + field);
    sample[field] = number;
  }
  if (!Number.isFinite(value.failover.lease_takeover_ms) || value.failover.lease_takeover_ms < 0) {
    throw new Error('Invalid synthetic failover duration');
  }
  sample.lease_takeover_ms = value.failover.lease_takeover_ms;
  return sample;
}

function platformTests() {
  const directories = [
    ['platform', '.test.cjs'], ['sdk/node', '.test.cjs'],
    ['examples/receiver-node', '.test.cjs'], ['examples/receiver-durable', '.test.cjs'],
    ['scripts', '.test.mjs'],
  ];
  return directories.flatMap(([directory, suffix]) => readdirSync(join(root, directory))
    .filter(name => name.endsWith(suffix)).map(name => join(root, directory, name)));
}

function runStep(role, scenario, args, iteration = 1) {
  const started = Date.now();
  const result = spawnSync(process.execPath, args, {cwd: root, env: process.env,
    encoding: 'utf8', maxBuffer: 8 * 1024 * 1024, timeout: 180000});
  let passed = !result.error && result.status === 0;
  let sample;
  if (passed && args.at(-1).endsWith('platform-showcase.mjs')) {
    try { sample = parseShowcaseSummary(result.stdout); }
    catch (_) { passed = false; }
  }
  console.log(`${passed ? 'PASS' : 'FAIL'} [${role}] ${scenario} (${Date.now() - started} ms)`);
  if (!passed) {
    mkdirSync(join(root, 'target'), {recursive: true});
    writeFileSync(join(root, 'target', 'simulated-pilot-failure.log'),
      `Step: ${args.at(-1)}\nExit: ${result.status ?? result.signal ?? result.error?.code ?? 'unknown'}\n` +
      `STDOUT:\n${result.stdout || ''}\nSTDERR:\n${result.stderr || result.error?.message || ''}\n`, {mode: 0o600});
    console.error(`Step failed: ${args.at(-1)}; inspect private target/simulated-pilot-failure.log`);
  }
  return {role, scenario, iteration, passed, durationMs: Date.now() - started, ...(sample ? {sample} : {})};
}

function main() {
  const {profile, repeat} = parseOptions(process.argv.slice(2));
  if (profile === 'full') validateTestDatabase(process.env.TEST_DATABASE_URL);
  const startedAt = new Date().toISOString();
  const results = [];
  const steps = [['reviewer', 'Node.js 单元与安全边界', ['--test', ...platformTests()]],
    ...gatewayScenarios.map(([role, name, file]) => [role, name, [join(root, 'scripts', file)]]),
  ];
  for (const [role, name, args] of steps) {
    const result = runStep(role, name, args);
    results.push(result);
    if (!result.passed) break;
  }
  if (profile === 'full' && results.every(result => result.passed)) {
    for (let iteration = 1; iteration <= repeat; iteration++) {
      for (const [role, name, file] of databaseScenarios) {
        const result = runStep(role, name, [join(root, 'scripts', file)], iteration);
        results.push(result);
        if (!result.passed) break;
      }
      if (!results.at(-1).passed) break;
    }
  }
  const report = {kind: 'synthetic-controlled-test-not-real-user-pilot', profile, repeat,
    startedAt, finishedAt: new Date().toISOString(),
    commit: process.env.GITHUB_SHA || null, results,
    passed: results.length === steps.length + (profile === 'full' ? databaseScenarios.length * repeat : 0) &&
      results.every(result => result.passed)};
  mkdirSync(join(root, 'target'), {recursive: true});
  writeFileSync(reportPath, JSON.stringify(report, null, 2) + '\n', {mode: 0o600});
  console.log(`Synthetic report: ${reportPath} (${results.length} scenario groups; passed=${report.passed})`);
  if (!report.passed) process.exitCode = 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
