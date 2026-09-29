import test from 'node:test';
import assert from 'node:assert/strict';
import {matchesLock} from './check-toolchain-lock.mjs';

test('toolchain lock requires both reviewed versions', () => {
  const good = 'moon 0.1.20260920 (914d7da 2026-09-20) /bin/moon\nmoonc v0.10.14+7d59c7ec9 (2026-09-18) /bin/moonc\n';
  assert.equal(matchesLock(good), true);
  assert.equal(matchesLock(good.replace('v0.10.14', 'v0.10.15')), false);
  assert.equal(matchesLock('moon 0.1.20260920 (914d7da 2026-09-20)'), false);
});
