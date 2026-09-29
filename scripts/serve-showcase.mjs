import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

const root = new URL('../docs/', import.meta.url);
const assets = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/index.html', ['index.html', 'text/html; charset=utf-8']],
  ['/showcase.css', ['showcase.css', 'text/css; charset=utf-8']],
  ['/showcase-responsive.css', ['showcase-responsive.css', 'text/css; charset=utf-8']],
  ['/showcase.js', ['showcase.js', 'text/javascript; charset=utf-8']],
  ['/showcase-model.mjs', ['showcase-model.mjs', 'text/javascript; charset=utf-8']],
]);
export function createShowcaseServer() { return createServer(async (request, response) => {
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('Cache-Control', 'no-store');
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    response.writeHead(405, {'Allow': 'GET, HEAD'}).end();
    return;
  }
  let pathname;
  try { pathname = new URL(request.url, 'http://127.0.0.1').pathname; }
  catch { response.writeHead(400).end(); return; }
  const asset = assets.get(pathname);
  if (!asset) { response.writeHead(404).end(); return; }
  try {
    const bytes = await readFile(fileURLToPath(new URL(asset[0], root)));
    response.writeHead(200, {'Content-Type': asset[1], 'Content-Length': bytes.length});
    response.end(request.method === 'HEAD' ? undefined : bytes);
  } catch {
    response.writeHead(500).end();
  }
}); }

if (fileURLToPath(import.meta.url) === resolve(process.argv[1] ?? '')) {
  const port = Number(process.env.HOOKLAB_SHOWCASE_PORT ?? 8789);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('HOOKLAB_SHOWCASE_PORT must be an integer from 1 to 65535');
  }
  createShowcaseServer().listen(port, '127.0.0.1', () => {
    process.stdout.write(`HookLab showcase: http://127.0.0.1:${port}/\n`);
  });
}
