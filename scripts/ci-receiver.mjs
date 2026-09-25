import http from 'node:http';

// Disposable synthetic receiver. This file is mounted only by compose.ci.yaml.
const attempts = [];
const server = http.createServer((request, response) => {
  if (request.method === 'GET' && request.url === '/health') {
    response.writeHead(200, {'content-type': 'application/json'});
    response.end('{"status":"ok"}');
    return;
  }
  if (request.method === 'GET' && request.url === '/state') {
    response.writeHead(200, {'content-type': 'application/json'});
    response.end(JSON.stringify(attempts));
    return;
  }
  if (request.method !== 'POST' || request.url !== '/sink') {
    response.writeHead(404);
    response.end();
    return;
  }
  const chunks = [];
  let size = 0;
  request.on('data', chunk => {
    size += chunk.length;
    if (size > 1024 * 1024) request.destroy();
    else chunks.push(chunk);
  });
  request.on('end', () => {
    const headers = Object.fromEntries(Object.entries(request.headers)
      .filter(([key]) => key.startsWith('x-hooklab-')));
    attempts.push({headers, body: Buffer.concat(chunks).toString('utf8')});
    const first = attempts.length === 1;
    response.writeHead(first ? 503 : 204, first ? {'retry-after': '0'} : {});
    response.end();
  });
});
// Host access remains bound to 127.0.0.1 by compose.ci.yaml; listen on the
// container interface so Docker's host-port forwarding can reach this probe.
server.listen(8766, '0.0.0.0');
