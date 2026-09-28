import assert from 'node:assert/strict';
import {test} from 'node:test';
import {checkDependencyLicenses} from './check-dependency-licenses.mjs';

test('accepts the reviewed lockfile license set', () => {
  assert.deepEqual(
    checkDependencyLicenses({packages: {'': {}, 'node_modules/a': {license: 'MIT'}}}),
    {count: 1, licenses: ['MIT']},
  );
});

test('fails closed on missing or new license metadata', () => {
  assert.throws(() => checkDependencyLicenses({}), /Missing/);
  assert.throws(() => checkDependencyLicenses({packages: {'': {}}}), /no dependency/);
  assert.throws(() => checkDependencyLicenses({packages: {'node_modules/a': {}}}), /missing or unreviewed/);
  assert.throws(() => checkDependencyLicenses({packages: {'node_modules/a': {license: 'GPL-3.0'}}}), /unreviewed/);
});
