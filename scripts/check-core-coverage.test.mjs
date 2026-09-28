import assert from 'node:assert/strict';
import {test} from 'node:test';
import {meetsCoverageFloor, parseCoverageSummary} from './check-core-coverage.mjs';

test('parses a single package summary despite file-level rows', () => {
  assert.deepEqual(
    parseCoverageSummary('hooklab\\crypto\\hmac.mbt: 43/47\r\nTotal: 101/105\r\n'),
    {covered: 101, total: 105},
  );
});

test('rejects absent, duplicate and impossible coverage totals', () => {
  assert.throws(() => parseCoverageSummary('no total'), /exactly one/);
  assert.throws(() => parseCoverageSummary('Total: 1/2\nTotal: 2/2\n'), /exactly one/);
  assert.throws(() => parseCoverageSummary('Total: 2/1\n'), /Invalid/);
  assert.throws(() => parseCoverageSummary('Total: 0/0\n'), /Invalid/);
});

test('coverage floor is inclusive and uses integer arithmetic', () => {
  assert.equal(meetsCoverageFloor({covered: 80, total: 100}, 80), true);
  assert.equal(meetsCoverageFloor({covered: 79, total: 100}, 80), false);
});
