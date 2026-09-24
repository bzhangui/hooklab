'use strict';

let tenant = '';
let token = '';
const byId = id => document.getElementById(id);
const show = (id, value) => { byId(id).textContent = JSON.stringify(value, null, 2); };
function notice(message) { byId('notice').textContent = message; }
async function api(path, method = 'GET', body) {
  const response = await fetch('/api/tenants/' + encodeURIComponent(tenant) + '/' + path, {
    method,
    headers: {'authorization': 'Bearer ' + token, ...(body ? {'content-type': 'application/json'} : {})},
    ...(body ? {body: JSON.stringify(body)} : {}),
  });
  const value = await response.json();
  if (!response.ok) throw new Error(value.error || 'HTTP ' + response.status);
  return value;
}
async function refresh() {
  const [catalog, events, deliveries, alerts, slo] = await Promise.all([
    api('catalog'), api('events'), api('deliveries'), api('alerts'), api('slo'),
  ]);
  show('catalog', catalog); show('events', events); show('deliveries', deliveries);
  show('alerts', alerts); show('slo', slo);
  notice('已连接：' + tenant);
}
byId('connection').addEventListener('submit', async event => {
  event.preventDefault();
  tenant = byId('tenant').value.trim(); token = byId('token').value.trim();
  byId('token').value = '';
  try { await refresh(); } catch (error) { notice(error.message); }
});
byId('disconnect').addEventListener('click', () => {
  tenant = ''; token = '';
  for (const id of ['catalog','events','deliveries','alerts','slo','action-result']) byId(id).textContent = '';
  notice('已断开');
});
byId('action').addEventListener('submit', async event => {
  event.preventDefault();
  if (!tenant || !token) return notice('请先连接租户');
  const operation = byId('operation').value;
  const id = byId('resource-id').value.trim();
  let path = operation;
  let body;
  if (operation.includes('/')) {
    if (!id) return notice('此操作需要目标 ID');
    const [resource, action] = operation.split('/');
    path = resource + '/' + encodeURIComponent(id) + '/' + action;
  } else {
    try { body = JSON.parse(byId('input').value); }
    catch (_) { return notice('JSON 参数格式错误'); }
  }
  try {
    const result = await api(path, 'POST', body);
    show('action-result', result);
    notice('操作成功。若返回令牌或密钥，请立即安全保存；此页面不会持久保存。');
    await refresh();
  } catch (error) { notice(error.message); }
});
