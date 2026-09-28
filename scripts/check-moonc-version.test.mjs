import assert from 'node:assert/strict';
import test from 'node:test';
import {atLeast, parseMooncVersion} from './check-moonc-version.mjs';

test('accepts the required compiler version and newer releases', () => {
  assert.deepEqual(parseMooncVersion('moonc v0.10.14+7d59c7ec9 (2026-09-18)'), [0, 10, 14]);
  assert.deepEqual(parseMooncVersion('v0.10.14+7d59c7ec9 (2026-09-18)'), [0, 10, 14]);
  assert.equal(atLeast([0, 10, 14], [0, 10, 14]), true);
  assert.equal(atLeast([0, 11, 0], [0, 10, 14]), true);
});

test('rejects older and unreadable compiler versions', () => {
  assert.equal(atLeast([0, 10, 13], [0, 10, 14]), false);
  assert.equal(atLeast([0, 9, 99], [0, 10, 14]), false);
  assert.throws(() => parseMooncVersion('moon 0.1.20260920'), /Could not read/);
});
