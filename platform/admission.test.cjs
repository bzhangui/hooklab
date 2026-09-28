'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {EventEmitter} = require('node:events');
const http = require('node:http');
const {parseMaxInflight, createAdmission} = require('./admission.cjs');

test('local overload limit rejects invalid values and defaults to disabled', () => {
  assert.equal(parseMaxInflight(undefined), 0);
  assert.equal(parseMaxInflight('2'), 2);
  for (const value of ['-1', '1.5', '01', '100000', 'NaN']) {
    assert.throws(() => parseMaxInflight(value));
  }
});

test('admission rejects before handler work and releases on response close', () => {
  const rejected = [];
  const admit = createAdmission(1, response => rejected.push(response));
  const first = new EventEmitter(), second = new EventEmitter();
  assert.equal(admit(first), true);
  assert.equal(admit(second), false);
  assert.deepEqual(rejected, [second]);
  assert.deepEqual(admit.stats, {active: 1, rejected: 1});
  first.emit('close');
  assert.equal(admit(second), true);
  second.emit('close');
  assert.equal(admit.stats.active, 0);
});

test('an overloaded HTTP request receives a retryable response', async () => {
  let release;
  let accepted;
  const acceptedPromise = new Promise(resolve => { accepted = resolve; });
  const pending = new Promise(resolve => { release = resolve; });
  const admit = createAdmission(1, response => {
    response.writeHead(503, {'retry-after': '1'});
    response.end('overloaded');
  });
  const server = http.createServer(async (request, response) => {
    if (!admit(response)) return;
    accepted();
    await pending;
    response.end('ok');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const base = 'http://127.0.0.1:' + server.address().port;
    const first = fetch(base);
    await acceptedPromise;
    const second = await fetch(base);
    assert.equal(second.status, 503);
    assert.equal(second.headers.get('retry-after'), '1');
    release();
    assert.equal((await first).status, 200);
    assert.equal(admit.stats.rejected, 1);
  } finally {
    release();
    await new Promise(resolve => server.close(resolve));
  }
});
