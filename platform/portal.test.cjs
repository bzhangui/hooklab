'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

class Element {
  constructor(tag = 'div') {
    this.tagName = tag;
    this._text = '';
    this.children = [];
    this.handlers = new Map();
    this.value = '';
    this.hidden = false;
    this.disabled = false;
    this.className = '';
    this.style = {};
    this.attributes = new Map();
    this.classList = {
      toggle: (name, enabled) => {
        const classes = new Set(this.className.split(/\s+/).filter(Boolean));
        if (enabled) classes.add(name);
        else classes.delete(name);
        this.className = [...classes].join(' ');
      },
    };
  }
  set textContent(value) { this._text = String(value); this.children = []; }
  get textContent() { return this._text + this.children.map(child => child.textContent).join(''); }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this._text = ''; this.children = children; }
  addEventListener(name, handler) { this.handlers.set(name, handler); }
  dispatch(name) { return this.handlers.get(name)({preventDefault() {}}); }
  setAttribute(name, value) { this.attributes.set(name, value); }
  removeAttribute(name) { this.attributes.delete(name); }
  scrollIntoView() {}
}

function portalHarness() {
  const elements = new Map();
  const get = id => {
    if (!elements.has(id)) elements.set(id, new Element());
    return elements.get(id);
  };
  get('operation').value = 'applications';
  get('delivery-filter').value = 'all';
  const fetched = [];
  const eventId = 'f92a3b35-7d20-40c9-98c1-d552c3004e44';
  const deliveryId = '8e2c52a4-9f6c-40b1-a511-258b04eb06bd';
  const fixtures = {
    catalog: {applications: [{id: 'orders', enabled: true}], endpoints: [{id: 'billing', url: 'https://example.com/hook', enabled: true}], subscriptions: [], contracts: []},
    events: [{id: eventId, application_id: 'orders', event_type: 'order.created', source: 'application', created_at: '2026-09-27T10:00:00Z'}],
    deliveries: [{id: deliveryId, event_id: eventId, endpoint_id: 'billing', state: 'dead_lettered', attempt: 3, created_at: '2026-09-27T10:01:00Z'}],
    alerts: [{id: 1, kind: 'dead_letter', state: 'open', message: '1 dead letter', opened_at: '2026-09-27T10:01:00Z'}],
    slo: {total: 1, delivered: 0, deadLettered: 1, deliverySuccessRatio: 0, p95FinalDeliveryLatencyMs: null, target: .99},
  };
  const fetch = async (url, options) => {
    fetched.push({url, options});
    const resource = url.split('/api/tenants/demo/')[1];
    let result = fixtures[resource];
    if (resource === 'applications' && options.method === 'POST') result = {id: 'more-orders', publishToken: 'once-only-secret'};
    if (resource === 'events/' + eventId + '/timeline') result = {event: fixtures.events[0], deliveries: fixtures.deliveries, attempts: [], truncated: false};
    if (result === undefined) return {ok: false, status: 404, json: async () => ({error: 'not_found'})};
    return {ok: true, status: 200, json: async () => result};
  };
  const document = {
    getElementById: get,
    createElement: tag => new Element(tag),
    querySelector: selector => get(selector),
    querySelectorAll: () => [],
  };
  const source = fs.readFileSync(path.join(__dirname, 'portal.js'), 'utf8');
  vm.runInNewContext(source, {document, fetch, window: {confirm: () => true}}, {filename: 'portal.js'});
  return {get, fetched, eventId};
}

test('portal connects, renders operational data, filters rows and clears one-time credentials', async () => {
  const {get, fetched} = portalHarness();
  get('tenant').value = 'demo';
  get('token').value = 'private-admin-token';
  await get('connection').dispatch('submit');
  assert.equal(get('token').value, '');
  assert.equal(get('tenant-chip').textContent, 'demo');
  assert.equal(get('metric-total').textContent, '1');
  assert.equal(get('metric-success').textContent, '0.0%');
  assert.match(get('event-rows').textContent, /order.created/);
  assert.match(get('delivery-rows').textContent, /死信/);
  assert.equal(fetched.length, 5);
  assert.ok(fetched.every(call => call.options.headers.authorization === 'Bearer private-admin-token'));

  get('event-search').value = 'does-not-exist';
  get('event-search').dispatch('input');
  assert.match(get('event-rows').textContent, /没有匹配/);
  get('event-search').value = '';
  get('event-search').dispatch('input');
  assert.match(get('event-rows').textContent, /order.created/);

  get('input').value = '{"id":"more-orders"}';
  await get('action').dispatch('submit');
  assert.match(get('action-result').textContent, /once-only-secret/);
  assert.ok(fetched.some(call => call.url.endsWith('/applications') && call.options.method === 'POST'));
  get('disconnect').dispatch('click');
  assert.equal(get('action-result').textContent, '');
  assert.equal(get('tenant-chip').textContent, '未连接');
  assert.equal(get('metric-total').textContent, '—');
  assert.equal(get('disconnect').disabled, true);
});

test('portal blocks malformed JSON before requesting a mutation', async () => {
  const {get, fetched} = portalHarness();
  get('tenant').value = 'demo';
  get('token').value = 'private-admin-token';
  await get('connection').dispatch('submit');
  get('input').value = '{bad json';
  await get('action').dispatch('submit');
  assert.match(get('notice').textContent, /JSON 参数格式错误/);
  assert.equal(fetched.filter(call => call.options.method === 'POST').length, 0);
});

test('portal has no external assets or browser credential storage', () => {
  const html = fs.readFileSync(path.join(__dirname, 'portal.html'), 'utf8');
  const script = fs.readFileSync(path.join(__dirname, 'portal.js'), 'utf8');
  assert.match(html, /消费者门户/);
  assert.match(html, /href="\/portal.css"/);
  assert.match(html, /src="\/portal.js"/);
  assert.doesNotMatch(html, /(?:src|href)="https?:\/\//i);
  assert.doesNotMatch(script, /localStorage|sessionStorage|document\.cookie/);
});
