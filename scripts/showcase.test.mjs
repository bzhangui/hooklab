import assert from 'node:assert/strict';
import {existsSync, readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';
import {once} from 'node:events';
import {getScenario, scenarios} from '../docs/showcase-model.mjs';
import {createShowcaseServer} from './serve-showcase.mjs';

const page = readFileSync(fileURLToPath(new URL('../docs/index.html', import.meta.url)), 'utf8');
const script = readFileSync(fileURLToPath(new URL('../docs/showcase.js', import.meta.url)), 'utf8');
const styles = readFileSync(fileURLToPath(new URL('../docs/showcase.css', import.meta.url)), 'utf8');

test('public teaching site is clearly synthetic and never calls a live API', () => {
  assert.match(page, /合成模拟/);
  assert.match(page, /不能替代真实用户试点|不代表真实用户试点/);
  assert.match(page, /connect-src 'none'/);
  assert.doesNotMatch(script, /\bfetch\s*\(|\bXMLHttpRequest\b|\bWebSocket\b|localStorage|sessionStorage/);
  for (const id of ['scenario-menu','timeline','play','reset','accepted','attempts','effects']) {
    assert.match(page, new RegExp(`id="${id}"`));
  }
  for (const asset of ['showcase.css', 'showcase-responsive.css', 'showcase.js', 'showcase-model.mjs', '.nojekyll']) {
    assert.equal(existsSync(fileURLToPath(new URL('../docs/' + asset, import.meta.url))), true);
  }
});

test('public tour keeps navigation, motion and accessibility usable without external assets', () => {
  assert.match(page, /class="skip-link" href="#main"/);
  for (const id of ['main', 'how-it-works', 'simulator']) {
    assert.match(page, new RegExp(`id="${id}"`));
  }
  assert.match(page, /id="state"[^>]*role="status"/);
  assert.match(styles, /prefers-reduced-motion:\s*reduce/);
  assert.match(script, /reducedMotion/);
  assert.doesNotMatch(page, /<(?:script|link)[^>]+(?:src|href)="https?:\/\//);
});

test('six personas show honest, internally consistent outcomes', () => {
  assert.equal(scenarios.length, 6);
  assert.equal(new Set(scenarios.map(item => item.id)).size, scenarios.length);
  assert.equal(getScenario('missing'), null);
  for (const scenario of scenarios) {
    assert.equal(getScenario(scenario.id), scenario);
    assert.ok(scenario.role && scenario.title && scenario.description);
    assert.ok(scenario.steps.length >= 4);
    assert.ok(['delivered','rejected','dead_lettered'].includes(scenario.outcome));
    if (scenario.outcome === 'rejected') {
      assert.equal(scenario.accepted, 0);
      assert.equal(scenario.attempts, 0);
      assert.equal(scenario.businessEffects, 0);
    }
    assert.ok(scenario.businessEffects <= scenario.accepted);
  }
  const retry = getScenario('retry');
  assert.equal(retry.attempts, 2);
  assert.equal(retry.businessEffects, 1);
});

test('loopback preview serves modules with browser-compatible MIME and no API', async () => {
  const server = createShowcaseServer().listen(0, '127.0.0.1');
  await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}`;
  try {
    const pageResponse = await fetch(url);
    assert.equal(pageResponse.status, 200);
    assert.match(pageResponse.headers.get('content-type'), /^text\/html/);
    assert.match(await pageResponse.text(), /connect-src 'none'/);
    const moduleResponse = await fetch(url + '/showcase-model.mjs');
    assert.equal(moduleResponse.status, 200);
    assert.match(moduleResponse.headers.get('content-type'), /^text\/javascript/);
    assert.equal((await fetch(url + '/api/tenants')).status, 404);
    assert.equal((await fetch(url, {method: 'POST'})).status, 405);
  } finally {
    await new Promise((resolveClose, rejectClose) => server.close(error => error ? rejectClose(error) : resolveClose()));
  }
});
