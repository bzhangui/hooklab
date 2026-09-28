import assert from 'node:assert/strict';
import {test} from 'node:test';
import {publishedPort} from './simulated-pilot-local.mjs';

test('disposable database port must be bound to loopback', () => {
  assert.equal(publishedPort('127.0.0.1:32768\n'), 32768);
  for (const output of ['0.0.0.0:32768', '[::]:32768', '127.0.0.1:0', '127.0.0.1:99999']) {
    assert.throws(() => publishedPort(output));
  }
});
