import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {basename, dirname, join} from 'node:path';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';

const temporaryParent = realpathSync(tmpdir());
const smokeRoot = mkdtempSync(join(temporaryParent, 'hooklab-mooncakes-'));
const expected = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
const expectedEventId = 'publish:' + createHash('sha256').update('orders\norder-42-created').digest('hex').slice(0, 24);

function moon(...args) {
  const result = spawnSync('moon', args, {
    cwd: smokeRoot,
    encoding: 'utf8',
    maxBuffer: 4 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    throw new Error(`moon ${args.join(' ')} failed:\n${result.stderr || result.error?.message || result.stdout}`);
  }
  return result.stdout.trim();
}

try {
  const registryVersion = () => {
    const response = JSON.parse(moon('view', 'bzhangui/hooklab', '--json'));
    if (response.status !== 'success' || !response.result?.latest_version) {
      throw new Error('Mooncakes did not return the latest published HookLab version');
    }
    return response.result.latest_version;
  };
  const version = process.argv[2] ?? registryVersion();
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(version)) {
    throw new Error('Expected a concrete Mooncakes version such as 0.3.0-rc.4');
  }
  mkdirSync(join(smokeRoot, 'cmd', 'main'), {recursive: true});
  writeFileSync(join(smokeRoot, 'moon.mod'), [
    'name = "bzhangui/hooklab-registry-smoke"',
    'version = "0.1.0"',
    'readme = "README.md"',
    'license = "MIT"',
    '',
  ].join('\n'));
  writeFileSync(join(smokeRoot, 'README.md'), '# Temporary HookLab consumer\n');
  writeFileSync(join(smokeRoot, 'cmd', 'main', 'moon.pkg'), [
    'import {',
    '  "bzhangui/hooklab/hooklab/crypto" @crypto,',
    '  "bzhangui/hooklab/hooklab/outbound" @outbound,',
    '}',
    'pkgtype(kind: "executable")',
    '',
  ].join('\n'));
  writeFileSync(join(smokeRoot, 'cmd', 'main', 'main.mbt'), [
    '///|',
    'fn main {',
    '  println(@crypto.sha256_hex("abc"))',
    '  let event_id = @outbound.publication_event_id("orders", "order-42-created")',
    '  let payload = "{\\"order_id\\":\\"order-42\\"}"',
    '  let signature = @outbound.sign_delivery("local-secret", 1700000000L, "delivery:example", event_id, "order.created", payload)',
    '  println(event_id)',
    '  println(@outbound.verify_delivery_signature(["local-secret"], signature, 1700000000L, "delivery:example", event_id, "order.created", payload))',
    '  println(@outbound.verify_delivery_signature(["local-secret"], signature, 1700000000L, "delivery:example", event_id, "order.created", "changed"))',
    '}',
    '',
  ].join('\n'));

  moon('add', `bzhangui/hooklab@${version}`);
  const manifest = readFileSync(join(smokeRoot, 'moon.mod'), 'utf8');
  if (!manifest.includes(`"bzhangui/hooklab@${version}"`)) {
    throw new Error('Mooncakes did not pin the requested published version');
  }
  moon('check', '--target', 'all', '--deny-warn');
  const actual = moon('run', '--target', 'js', 'cmd/main');
  if (actual !== [expected, expectedEventId, 'true', 'false'].join('\n')) {
    throw new Error(`Unexpected published package result: ${actual}`);
  }
  console.log(`Mooncakes consumer passed: bzhangui/hooklab@${version}, all-target check, SHA-256, event ID and outbound signature`);
} finally {
  const resolved = realpathSync(smokeRoot);
  if (dirname(resolved) !== temporaryParent || !basename(resolved).startsWith('hooklab-mooncakes-')) {
    throw new Error(`Refusing to remove unexpected smoke directory: ${resolved}`);
  }
  rmSync(resolved, {recursive: true});
}
