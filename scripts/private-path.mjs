import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

export function restrictPrivatePath(target) {
  if (process.platform !== 'win32') return;
  const identity = spawnSync('whoami.exe', ['/user', '/fo', 'csv', '/nh'],
    {windowsHide: true, encoding: 'utf8'});
  const sid = identity.stdout?.match(/S-1-5(?:-\d+)+/)?.[0];
  if (identity.status !== 0 || !sid) throw new Error('Could not identify the current Windows user');
  const permission = fs.statSync(target).isDirectory() ? '(OI)(CI)F' : 'F';
  for (const args of [
    [target, '/grant:r', '*' + sid + ':' + permission,
      '*S-1-5-18:' + permission, '*S-1-5-32-544:' + permission],
    [target, '/inheritance:r'],
  ]) {
    const result = spawnSync('icacls.exe', args, {windowsHide: true, encoding: 'utf8'});
    if (result.status !== 0) {
      throw new Error('Could not restrict Windows permissions for ' + path.basename(target));
    }
  }
}
