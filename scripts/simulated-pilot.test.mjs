import assert from 'node:assert/strict';
import {test} from 'node:test';
import {parseOptions, parseShowcaseSummary, validateTestDatabase} from './simulated-pilot.mjs';

test('simulation refuses production and remote databases', () => {
  assert.equal(validateTestDatabase('postgresql://postgres:secret@127.0.0.1:5432/hooklab_test'), true);
  for (const url of [undefined, 'garbage', 'postgresql://db.example.com/hooklab_test',
    'postgresql://127.0.0.1/production', 'postgresql://127.0.0.1/hooklab_test-extra']) {
    assert.throws(() => validateTestDatabase(url));
  }
});

test('simulation requires an explicit bounded repeat count', () => {
  assert.deepEqual(parseOptions([]), {profile: 'quick', repeat: 1});
  assert.deepEqual(parseOptions(['--profile', 'full', '--repeat', '2']), {profile: 'full', repeat: 2});
  for (const args of [['--profile','production'], ['--repeat','0'], ['--repeat','31'],
    ['--unknown','1'], ['--repeat','2','--repeat','3'], ['--profile'],
    ['--profile','quick','--repeat','2']]) assert.throws(() => parseOptions(args));
});

test('only verified synthetic numbers enter the public summary', () => {
  const payload = JSON.stringify({scenario: 'synthetic_loopback_order_delivery',
    contract_rejection_without_persistence: true,
    failover: {same_delivery_id: true, receiver_signatures_verified: true,
      deduplicated_consumer_ids: 1, final_state: 'delivered', lease_takeover_ms: 30100},
    local_sample: {events: 32, publish_batch_ms: 300, publish_p50_ms: 80,
      publish_p95_ms: 110, all_delivered_ms: 450, privateBody: 'must-not-copy'}});
  const safe = parseShowcaseSummary(payload);
  assert.equal(safe.events, 32);
  assert.equal(safe.lease_takeover_ms, 30100);
  assert.equal(JSON.stringify(safe).includes('must-not-copy'), false);
  assert.throws(() => parseShowcaseSummary(payload.replace('"delivered"', '"pending"')));
});
