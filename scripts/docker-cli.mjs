import fs from 'node:fs';
import path from 'node:path';

// Docker Desktop's per-user installer can be available before PATH is refreshed.
export function dockerCommand(env = process.env, exists = fs.existsSync, platform = process.platform) {
  if (platform !== 'win32') return 'docker';
  for (const base of [
    env.LOCALAPPDATA && path.join(env.LOCALAPPDATA, 'Programs', 'DockerDesktop'),
    env.ProgramFiles && path.join(env.ProgramFiles, 'Docker', 'Docker'),
    env['ProgramFiles(x86)'] && path.join(env['ProgramFiles(x86)'], 'Docker', 'Docker'),
  ]) {
    if (!base) continue;
    const candidate = path.join(base, 'resources', 'bin', 'docker.exe');
    if (exists(candidate)) return candidate;
  }
  return 'docker';
}

export function dockerEnvironment(command, env = process.env, platform = process.platform) {
  if (platform !== 'win32' || command === 'docker') return env;
  const key = Object.keys(env).find(name => name.toLowerCase() === 'path') || 'Path';
  return {...env, [key]: path.dirname(command) + path.delimiter + (env[key] || '')};
}
