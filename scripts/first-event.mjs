import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseLocalPort} from './doctor.mjs';

const root = path.resolve(import.meta.dirname, '..');
const identifier = /^[a-z][a-z0-9_-]{1,63}$/;
const eventTypePattern = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/;

export function firstEventRequest({tenant, application, type, port, token, body, key}) {
  if (!identifier.test(tenant) || !identifier.test(application) || !eventTypePattern.test(type)) {
    throw new Error('租户、应用或事件类型不符合格式要求');
  }
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('本机端口无效');
  if (typeof token !== 'string' || token.length < 32) throw new Error('缺少 HOOKLAB_PUBLISH_TOKEN');
  if (Buffer.byteLength(body, 'utf8') > 1024 * 1024) throw new Error('事件正文超过 1 MiB');
  const parsed = JSON.parse(body);
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('事件正文必须是 JSON 对象');
  return {
    url: 'http://127.0.0.1:' + port + '/api/tenants/' + tenant +
      '/applications/' + application + '/events/' + encodeURIComponent(type),
    options: {method: 'POST', headers: {
      authorization: 'Bearer ' + token,
      'content-type': 'application/json',
      'idempotency-key': key,
    }, body},
  };
}

function argumentsFrom(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    if (!['--tenant', '--application', '--type', '--body'].includes(argv[index]) ||
      !argv[index + 1] || Object.hasOwn(values, argv[index])) {
      throw new Error('用法：npm run first:event -- --tenant <租户> --application <应用> --type <事件类型> [--body <JSON 文件>]');
    }
    values[argv[index]] = argv[index + 1];
  }
  if (!values['--tenant'] || !values['--application'] || !values['--type']) {
    throw new Error('请提供 --tenant、--application 和 --type');
  }
  return values;
}

export async function runFirstEvent(argv, environment = process.env) {
  const args = argumentsFrom(argv);
  const envPath = path.join(root, '.env');
  const port = fs.existsSync(envPath) ? parseLocalPort(fs.readFileSync(envPath, 'utf8')) : 8787;
  const bodyPath = args['--body'] ? path.resolve(args['--body']) :
    path.join(root, 'examples', 'platform', 'order-created.json');
  const body = fs.readFileSync(bodyPath, 'utf8');
  const request = firstEventRequest({tenant: args['--tenant'], application: args['--application'],
    type: args['--type'], port, token: environment.HOOKLAB_PUBLISH_TOKEN,
    body, key: crypto.randomUUID()});
  const response = await fetch(request.url, {...request.options, signal: AbortSignal.timeout(10000)});
  let result;
  try { result = await response.json(); }
  catch (_) { throw new Error('服务未返回 JSON；请运行 npm run doctor 检查本机服务'); }
  if (!response.ok) throw new Error('发布失败：HTTP ' + response.status + ' · ' + (result.error || '未知错误'));
  console.log('事件已接受：' + result.eventId + '；已创建交付：' + result.deliveries +
    '。回到门户刷新并查看事件轨迹。');
  if (!result.deliveries) console.log('没有匹配的启用订阅；检查应用、事件类型与端点状态。');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { await runFirstEvent(process.argv.slice(2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
