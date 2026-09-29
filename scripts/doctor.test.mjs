import assert from 'node:assert/strict';
import test from 'node:test';
import {parseLocalPort, healthStatus} from './doctor.mjs';

test('port parser accepts only one valid port and never exposes other env entries', () => {
  assert.equal(parseLocalPort('HOOKLAB_BOOTSTRAP_TOKEN=private\n'), 8787);
  assert.equal(parseLocalPort('HOOKLAB_PORT=9123\nHOOKLAB_ENCRYPTION_KEY=private\n'), 9123);
  assert.throws(() => parseLocalPort('HOOKLAB_PORT=0\n'), /invalid/);
  assert.throws(() => parseLocalPort('HOOKLAB_PORT=8787\nHOOKLAB_PORT=9999\n'), /duplicate/);
});

test('health check requires HTTP 200 and explicit ready status', () => {
  assert.equal(healthStatus(200, '{"status":"ok"}').ok, true);
  assert.equal(healthStatus(503, '{"status":"ok"}').ok, false);
  assert.equal(healthStatus(200, '{"status":"starting"}').ok, false);
  assert.equal(healthStatus(200, 'not json').ok, false);
});
