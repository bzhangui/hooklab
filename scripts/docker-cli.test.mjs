import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import {dockerCommand, dockerEnvironment} from './docker-cli.mjs';

test('finds per-user Docker Desktop and its credential helper directory on Windows', () => {
  const env = {LOCALAPPDATA: 'C:\\Users\\demo\\AppData\\Local', Path: 'C:\\Windows'};
  const command = path.join(env.LOCALAPPDATA, 'Programs', 'DockerDesktop', 'resources', 'bin', 'docker.exe');
  assert.equal(dockerCommand(env, candidate => candidate === command, 'win32'), command);
  const child = dockerEnvironment(command, env, 'win32');
  assert.equal(child.Path, path.dirname(command) + path.delimiter + env.Path);
  assert.equal(env.Path, 'C:\\Windows');
});

test('uses PATH lookup on non-Windows hosts', () => {
  assert.equal(dockerCommand({}, () => false, 'linux'), 'docker');
  const env = {PATH: '/usr/bin'};
  assert.equal(dockerEnvironment('docker', env, 'linux'), env);
});
