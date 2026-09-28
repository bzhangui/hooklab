'use strict';

let tenant = '';
let token = '';
let session = 0;
let snapshot = {catalog: null, events: [], deliveries: [], alerts: [], slo: null};
const byId = id => document.getElementById(id);
const setText = (id, value) => { byId(id).textContent = String(value); };
const node = (tag, className, value) => {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (value !== undefined) element.textContent = String(value);
  return element;
};
const shortId = value => String(value || '—').slice(0, 8);
const dateText = value => {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? String(value) : date.toLocaleString('zh-CN', {hour12: false});
};
const durationText = value => value == null ? '—' : value < 1000 ? Math.round(value) + ' ms' : (value / 1000).toFixed(2) + ' s';
const stateLabels = {pending: '待交付', in_flight: '交付中', delivered: '已交付', dead_lettered: '死信'};
const errorLabels = {unauthorized: '认证失败，请核对租户 ID 与令牌。', forbidden: '当前令牌没有执行此操作的权限。', not_found: '未找到对应资源。', conflict: '资源状态冲突，请刷新后再试。', invalid_id: '目标 ID 格式不正确。', invalid_body: '参数不符合接口要求。', invalid_schema: '事件契约格式或兼容性不符合要求。'};
const operations = {
  applications: {hint: '创建应用时只需提供应用 ID。', sample: {id: 'orders'}},
  endpoints: {hint: '端点通常需要公网 HTTPS 地址；回环地址仅可用于显式启用的本机测试。', sample: {id: 'billing', url: 'https://your-domain.example/webhook'}},
  subscriptions: {hint: '订阅连接一个应用和一个端点，eventTypes 可填写具体类型或 *。', sample: {id: 'orders-billing', applicationId: 'orders', endpointId: 'billing', eventTypes: ['order.created']}},
  contracts: {hint: '发布版本递增的事件契约；schema 只支持平台文档列出的关键字。', sample: {applicationId: 'orders', eventType: 'order.created', version: 1, requireCloudEvents: false, schema: {type: 'object', required: ['orderId'], properties: {orderId: {type: 'string'}}}}},
  'provider-credentials': {hint: '保存第三方回调验签凭据；secret 至少 16 个字符，提交后不会回显。', sample: {applicationId: 'orders', provider: 'generic-hmac', secret: ''}},
  'applications/rotate-token': {hint: '输入应用 ID。新发布令牌仅显示一次，旧令牌会立即失效。'},
  'endpoints/rotate-secret': {hint: '输入端点 ID。新签名密钥仅显示一次；消费者应在过渡期兼容旧 keyId。'},
  'deliveries/retry': {hint: '输入死信交付的 UUID。重试将把它重新置为待交付。'},
};

function notice(message, error = false) {
  const target = byId('notice');
  target.textContent = message;
  target.classList.toggle('error', error);
  target.hidden = !message;
}
function humanError(error) {
  return errorLabels[error.message] || error.message || '请求失败，请稍后重试。';
}
async function api(path, method = 'GET', body) {
  const response = await fetch('/api/tenants/' + encodeURIComponent(tenant) + '/' + path, {
    method,
    headers: {'authorization': 'Bearer ' + token, ...(body === undefined ? {} : {'content-type': 'application/json'})},
    ...(body === undefined ? {} : {body: JSON.stringify(body)}),
  });
  let value;
  try { value = await response.json(); }
  catch (_) { throw new Error('服务器返回了无法读取的响应。'); }
  if (!response.ok) throw new Error(value.error || 'HTTP ' + response.status);
  return value;
}
function setConnected(connected) {
  byId('refresh').disabled = !connected;
  byId('disconnect').disabled = !connected;
  setText('tenant-chip', connected ? tenant : '未连接');
  setText('sidebar-connection', connected ? '已连接 · ' + tenant : '尚未连接租户');
  document.querySelector('.live-dot').classList.toggle('connected', connected);
}
function statusPill(state) {
  return node('span', 'status status-' + (Object.hasOwn(stateLabels, state) ? state : 'pending'), stateLabels[state] || state || '未知');
}
function empty(target, text, columns) {
  target.replaceChildren();
  const row = node('tr');
  const cell = node('td', 'table-empty', text);
  cell.colSpan = columns;
  row.append(cell);
  target.append(row);
}
function cell(text, className) {
  return node('td', className || '', text);
}
function actionButton(text, handler, danger = false) {
  const button = node('button', 'text-button' + (danger ? ' danger' : ''), text);
  button.type = 'button';
  button.addEventListener('click', handler);
  return button;
}
function renderSlo(slo) {
  const total = Number(slo.total || 0);
  const ratio = slo.deliverySuccessRatio;
  const percent = ratio == null ? null : Math.max(0, Math.min(100, ratio * 100));
  const percentText = percent == null ? '—' : percent.toFixed(1) + '%';
  setText('metric-total', total.toLocaleString('zh-CN'));
  setText('metric-success', percentText);
  setText('metric-dead', Number(slo.deadLettered || 0).toLocaleString('zh-CN'));
  setText('metric-latency', durationText(slo.p95FinalDeliveryLatencyMs));
  setText('health-rate', percentText);
  setText('health-breakdown', Number(slo.delivered || 0) + ' 已交付 · ' + Number(slo.deadLettered || 0) + ' 死信 · ' + Math.max(0, total - Number(slo.delivered || 0) - Number(slo.deadLettered || 0)) + ' 处理中');
  byId('health-progress').style.width = (percent || 0) + '%';
  const track = document.querySelector('.progress-track');
  if (percent == null) track.removeAttribute('aria-valuenow');
  else track.setAttribute('aria-valuenow', String(Math.round(percent)));
  const badge = byId('health-badge');
  badge.className = 'pill ' + (percent == null ? 'pill-neutral' : percent >= Number(slo.target || .99) * 100 ? 'pill-good' : 'pill-warning');
  badge.textContent = percent == null ? '暂无样本' : percent >= Number(slo.target || .99) * 100 ? '达到目标' : '低于目标';
}
function renderAlerts(alerts) {
  const open = alerts.filter(item => item.state === 'open');
  setText('alert-count', open.length);
  const list = byId('alert-list');
  list.replaceChildren();
  if (!open.length) {
    const emptyBox = node('div', 'empty-state');
    emptyBox.append(node('span', 'empty-icon', '✓'), node('strong', '', '当前没有未解决告警'), node('p', '', '需要关注的问题会在这里出现。'));
    list.append(emptyBox);
    return;
  }
  for (const item of open) {
    const entry = node('div', 'alert-item');
    entry.append(node('strong', '', item.kind || '平台告警'), node('p', '', item.message || '请检查运行状态'), node('small', '', dateText(item.opened_at)));
    list.append(entry);
  }
}
function renderEvents() {
  const items = snapshot.events;
  const query = byId('event-search').value.trim().toLowerCase();
  const filtered = items.filter(item => [item.id, item.event_type, item.application_id, item.provider].some(value => String(value || '').toLowerCase().includes(query)));
  setText('event-count', items.length);
  const rows = byId('event-rows');
  if (!filtered.length) return empty(rows, items.length ? '没有匹配的事件' : '暂无事件', 5);
  rows.replaceChildren();
  for (const item of filtered) {
    const row = node('tr');
    const main = cell();
    main.append(node('strong', '', item.event_type || '未命名事件'));
    const id = node('span', 'subtext mono', item.id || '—');
    main.append(id);
    row.append(main, cell(item.application_id || '—'), cell(item.provider || item.source || '应用'), cell(dateText(item.created_at)));
    const actions = cell();
    actions.className = 'align-right';
    const buttons = node('div', 'row-actions');
    buttons.append(actionButton('查看轨迹 ↗', () => {
      byId('timeline-id').value = item.id;
      byId('timeline-section').scrollIntoView({behavior: 'smooth', block: 'start'});
      loadTimeline(item.id);
    }));
    actions.append(buttons);
    row.append(actions);
    rows.append(row);
  }
}
function renderDeliveries() {
  const items = snapshot.deliveries;
  const query = byId('delivery-search').value.trim().toLowerCase();
  const filter = byId('delivery-filter').value;
  const filtered = items.filter(item => (filter === 'all' || item.state === filter) && [item.id, item.event_id, item.endpoint_id, item.subscription_id].some(value => String(value || '').toLowerCase().includes(query)));
  setText('delivery-count', items.length);
  const rows = byId('delivery-rows');
  if (!filtered.length) return empty(rows, items.length ? '没有匹配的交付' : '暂无交付', 6);
  rows.replaceChildren();
  for (const item of filtered) {
    const row = node('tr');
    const id = cell();
    const idLabel = node('strong', 'mono', shortId(item.id));
    idLabel.title = item.id;
    id.append(idLabel, node('span', 'subtext mono', '事件 ' + shortId(item.event_id)));
    const target = cell();
    target.append(node('strong', '', item.endpoint_id || '—'), node('span', 'subtext truncate', item.target_url || '—'));
    row.append(id, target);
    const status = cell();
    status.append(statusPill(item.state));
    row.append(status, cell(item.attempt ?? '—'), cell(dateText(item.created_at)));
    const actions = cell();
    actions.className = 'align-right';
    const buttons = node('div', 'row-actions');
    buttons.append(actionButton('事件轨迹', () => {
      byId('timeline-id').value = item.event_id;
      byId('timeline-section').scrollIntoView({behavior: 'smooth', block: 'start'});
      loadTimeline(item.event_id);
    }));
    if (item.state === 'dead_lettered') buttons.append(actionButton('重试', () => retryDelivery(item.id), true));
    actions.append(buttons);
    row.append(actions);
    rows.append(row);
  }
}
function renderResources(catalog) {
  const groups = [
    ['applications', 'app-list', 'app-count', item => item.enabled === false ? '已停用' : '运行中'],
    ['endpoints', 'endpoint-list', 'endpoint-count', item => item.url || '—'],
    ['subscriptions', 'subscription-list', 'subscription-count', item => (item.application_id || '—') + ' → ' + (item.endpoint_id || '—')],
  ];
  for (const [key, listId, countId, subtitle] of groups) {
    const values = Array.isArray(catalog[key]) ? catalog[key] : [];
    setText(countId, values.length);
    const list = byId(listId);
    list.replaceChildren();
    if (!values.length) { list.append(node('p', 'muted', '暂无资源')); continue; }
    for (const item of values) {
      const entry = node('div', 'resource-entry' + (item.enabled === false ? ' inactive' : ''));
      entry.append(node('strong', '', item.id || '—'), node('small', '', subtitle(item)));
      list.append(entry);
    }
  }
  const active = (catalog.contracts || []).filter(item => item.active);
  setText('contract-summary', active.length ? active.length + ' 个活跃版本 · ' + active.slice(0, 3).map(item => item.event_type + ' v' + item.version).join('，') + (active.length > 3 ? ' 等' : '') : '暂无活跃契约');
  for (const [key, id] of [['applications', 'onboarding-app-state'], ['endpoints', 'onboarding-endpoint-state'], ['subscriptions', 'onboarding-subscription-state']]) {
    const count = Array.isArray(catalog[key]) ? catalog[key].length : 0;
    setText(id, count ? '已创建 ' + count : '尚未创建');
  }
}
function render() {
  renderSlo(snapshot.slo);
  renderAlerts(snapshot.alerts);
  renderEvents();
  renderDeliveries();
  renderResources(snapshot.catalog);
  setText('updated-at', '更新于 ' + new Date().toLocaleTimeString('zh-CN', {hour12: false}));
}
async function refresh() {
  if (!tenant || !token) throw new Error('请先连接租户');
  const current = session;
  const [catalog, events, deliveries, alerts, slo] = await Promise.all([
    api('catalog'), api('events'), api('deliveries'), api('alerts'), api('slo'),
  ]);
  if (current !== session) return;
  snapshot = {catalog, events, deliveries, alerts, slo};
  setConnected(true);
  render();
}
function reset() {
  session++;
  tenant = '';
  token = '';
  snapshot = {catalog: null, events: [], deliveries: [], alerts: [], slo: null};
  byId('tenant').value = '';
  byId('token').value = '';
  byId('timeline-id').value = '';
  byId('resource-id').value = '';
  byId('input').value = '';
  byId('event-search').value = '';
  byId('delivery-search').value = '';
  byId('delivery-filter').value = 'all';
  byId('action-result').replaceChildren();
  byId('action-result').hidden = true;
  byId('timeline').replaceChildren();
  byId('timeline').append(node('div', 'empty-state compact', '连接后可查询事件轨迹'));
  for (const id of ['metric-total', 'metric-success', 'metric-dead', 'metric-latency', 'health-rate', 'event-count', 'delivery-count', 'alert-count', 'app-count', 'endpoint-count', 'subscription-count']) setText(id, '—');
  for (const id of ['app-list', 'endpoint-list', 'subscription-list', 'alert-list']) { byId(id).replaceChildren(node('p', 'muted', '等待连接')); }
  empty(byId('event-rows'), '连接租户后查看事件', 5);
  empty(byId('delivery-rows'), '连接租户后查看交付', 6);
  setText('health-breakdown', '连接后显示交付状态');
  setText('contract-summary', '连接后显示');
  for (const id of ['onboarding-app-state', 'onboarding-endpoint-state', 'onboarding-subscription-state']) setText(id, '待连接');
  setText('updated-at', '等待连接');
  byId('health-progress').style.width = '0%';
  byId('health-badge').className = 'pill pill-neutral';
  setText('health-badge', '等待数据');
  document.querySelector('.progress-track').removeAttribute('aria-valuenow');
  setConnected(false);
}
async function loadTimeline(id) {
  if (!tenant || !token) return notice('请先连接租户', true);
  const current = session;
  const target = byId('timeline');
  target.replaceChildren(node('div', 'empty-state compact', '正在查询事件轨迹…'));
  try {
    const result = await api('events/' + encodeURIComponent(id) + '/timeline');
    if (current !== session) return;
    target.replaceChildren();
    const summary = node('div', 'timeline-summary');
    summary.append(node('strong', '', result.event.event_type + ' · ' + result.event.application_id), node('small', 'mono', result.event.id + ' · ' + dateText(result.event.created_at)));
    target.append(summary);
    for (const delivery of result.deliveries) {
      const item = node('div', 'trace-item');
      item.append(node('strong', '', (delivery.endpoint_id || '端点') + ' · ' + (stateLabels[delivery.state] || delivery.state)), node('p', '', '交付 ' + delivery.id + ' · 已尝试 ' + delivery.attempt + ' 次'), node('small', '', dateText(delivery.updated_at)));
      if (delivery.last_error) item.append(node('p', '', '最近错误：' + delivery.last_error));
      target.append(item);
      for (const attempt of result.attempts.filter(value => value.delivery_id === delivery.id)) {
        const step = node('div', 'trace-item');
        step.append(node('strong', '', '第 ' + attempt.attempt + ' 次尝试 · ' + (attempt.outcome || '未知')), node('p', '', 'HTTP ' + (attempt.status ?? '—') + ' · ' + durationText(attempt.duration_ms)), node('small', '', dateText(attempt.created_at)));
        target.append(step);
      }
    }
    if (!result.deliveries.length) target.append(node('div', 'empty-state compact', '此事件暂无交付记录'));
    if (result.truncated) target.append(node('p', 'muted', '仅展示前 500 次尝试记录。'));
    notice('');
  } catch (error) {
    if (current !== session) return;
    target.replaceChildren(node('div', 'empty-state compact', '未能加载事件轨迹'));
    notice(humanError(error), true);
  }
}
async function retryDelivery(id) {
  if (!tenant || !token) return notice('请先连接租户', true);
  if (!window.confirm('确定重新投递这条死信吗？接收方可能收到重复事件。')) return;
  const current = session;
  try {
    await api('deliveries/' + encodeURIComponent(id) + '/retry', 'POST');
    if (current !== session) return;
    try { await refresh(); }
    catch (error) { if (current === session) notice('重试已提交，但列表刷新失败：' + humanError(error), true); return; }
    if (current === session) notice('已将死信重新放入待交付队列。');
  } catch (error) { if (current === session) notice(humanError(error), true); }
}
function operationChanged() {
  const operation = byId('operation').value;
  const targeted = operation.includes('/');
  byId('resource-id-field').hidden = !targeted;
  byId('resource-id').required = targeted;
  byId('json-field').hidden = targeted;
  setText('operation-hint', operations[operation].hint);
}
byId('connection').addEventListener('submit', async event => {
  event.preventDefault();
  session++;
  tenant = byId('tenant').value.trim();
  token = byId('token').value.trim();
  byId('token').value = '';
  byId('action-result').replaceChildren();
  byId('action-result').hidden = true;
  byId('timeline').replaceChildren();
  notice('正在连接租户…');
  const current = session;
  try {
    await refresh();
    if (current === session) notice('已连接 ' + tenant + '，数据已更新。');
  } catch (error) {
    if (current !== session) return;
    reset();
    notice(humanError(error), true);
  }
});
byId('disconnect').addEventListener('click', () => { reset(); notice('已断开租户连接，页面中的一次性凭据已清除。'); });
byId('refresh').addEventListener('click', async () => {
  try { await refresh(); notice('数据已更新。'); }
  catch (error) { notice(humanError(error), true); }
});
byId('event-search').addEventListener('input', renderEvents);
byId('delivery-search').addEventListener('input', renderDeliveries);
byId('delivery-filter').addEventListener('change', renderDeliveries);
byId('timeline-form').addEventListener('submit', event => {
  event.preventDefault();
  loadTimeline(byId('timeline-id').value.trim());
});
byId('operation').addEventListener('change', operationChanged);
for (const link of document.querySelectorAll('.nav-link')) {
  link.addEventListener('click', () => {
    for (const item of document.querySelectorAll('.nav-link')) item.classList.toggle('active', item === link);
    setText('breadcrumb-current', link.dataset.label);
  });
}
byId('example').addEventListener('click', () => {
  byId('input').value = JSON.stringify(operations[byId('operation').value].sample, null, 2);
  byId('input').focus();
});
for (const button of document.querySelectorAll('.onboarding-example')) {
  button.addEventListener('click', () => {
    const operation = button.dataset.operation;
    if (!Object.hasOwn(operations, operation) || !operations[operation].sample) return;
    byId('operation').value = operation;
    operationChanged();
    byId('input').value = JSON.stringify(operations[operation].sample, null, 2);
    byId('operations').scrollIntoView({behavior: 'smooth', block: 'start'});
    notice('已填入示例，请核对并修改参数，再自行提交。');
  });
}
byId('action').addEventListener('submit', async event => {
  event.preventDefault();
  if (!tenant || !token) return notice('请先连接租户', true);
  const operation = byId('operation').value;
  const id = byId('resource-id').value.trim();
  let path = operation;
  let body;
  if (operation.includes('/')) {
    if (!id) return notice('请填写目标 ID', true);
    const [resource, action] = operation.split('/');
    path = resource + '/' + encodeURIComponent(id) + '/' + action;
  } else {
    try { body = JSON.parse(byId('input').value); }
    catch (_) { return notice('JSON 参数格式错误', true); }
    if (!body || Array.isArray(body) || typeof body !== 'object') return notice('JSON 参数必须是对象', true);
  }
  const current = session;
  try {
    const result = await api(path, 'POST', body);
    if (current !== session) return;
    const output = byId('action-result');
    output.replaceChildren(node('strong', '', '操作成功 · 请留意一次性凭据'), node('pre', '', JSON.stringify(result, null, 2)));
    output.hidden = false;
    byId('input').value = '';
    try { await refresh(); }
    catch (error) { if (current === session) notice('操作成功，但列表刷新失败：' + humanError(error), true); return; }
    if (current === session) notice('操作成功。若返回令牌或密钥，请立即安全保存；断开后会从页面清除。');
  } catch (error) { if (current === session) notice(humanError(error), true); }
});
operationChanged();
