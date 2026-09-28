import assert from 'node:assert/strict';
import test from 'node:test';
import {verifyPackageList} from './check-package-contents.mjs';

const required = 'moon.mod\nREADME.md\nLICENSE\nhooklab\\core\\types.mbt\n';

test('accepts the reproducible public source archive', () => {
  assert.doesNotThrow(() => verifyPackageList(required + 'docs/DEMO.md\n'));
});

test('rejects private application, credentials and backup paths', () => {
  for (const privatePath of ['项目申报书.md', '.env', '.env.portal-local', 'backups/dump.sql',
    'snapshot.dump', 'node_modules/pg/index.js']) {
    assert.throws(() => verifyPackageList(required + privatePath), /Private file/);
  }
});
