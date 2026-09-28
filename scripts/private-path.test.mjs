import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {restrictPrivatePath} from './private-path.mjs';

test('Windows private files can be restricted without administrator privileges',
  {skip: process.platform !== 'win32'}, () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hooklab-private-'));
    const file = path.join(directory, 'credential.txt');
    try {
      fs.writeFileSync(file, 'synthetic-test-value');
      assert.doesNotThrow(() => restrictPrivatePath(file));
      assert.equal(fs.readFileSync(file, 'utf8'), 'synthetic-test-value');
    } finally {
      fs.unlinkSync(file);
      fs.rmdirSync(directory);
    }
  });
