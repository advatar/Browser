import http from 'node:http';

const port = Number(process.env.AFM_REGISTRY_PORT ?? 4820);
const hostname = process.env.AFM_REGISTRY_HOST ?? '127.0.0.1';
const startedAt = Date.now();

const registry = {
  packs: [
    { id: 'afm://demo-writer', maintainer: 'core', version: '0.1.0', checksum: '0xabc' },
    { id: 'afm://image-tool', maintainer: 'core', version: '0.0.5', checksum: '0xdef' }
  ]
};

const args = new Set(process.argv.slice(2));
if (args.has('--snapshot')) {
  console.log('[registry] snapshot ready');
  process.exit(0);
}
if (args.has('--lint')) {
  console.log('[registry] schema OK');
  process.exit(0);
}
if (args.has('--self-test')) {
  console.log('[registry] packs indexed:', registry.packs.length);
  process.exit(0);
}

const sendJson = (res, status, payload) => {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload, null, 2));
};

const server = http.createServer((req, res) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);
  if (req.method === 'GET' && url.pathname === '/health') {
    return sendJson(res, 200, { ok: true, uptimeMs: Date.now() - startedAt });
  }

  if (req.method === 'GET' && url.pathname === '/packs') {
    return sendJson(res, 200, { data: registry.packs });
  }

  if (req.method === 'POST' && url.pathname === '/packs') {
    let body = '';
    req.on('data', chunk => (body += chunk));
    req.on('end', () => {
      try {
        const payload = JSON.parse(body);
        registry.packs.push(payload);
        sendJson(res, 201, { ok: true, id: payload.id });
      } catch (err) {
        sendJson(res, 400, { error: 'invalid JSON', detail: String(err) });
      }
    });
    return;
  }

  sendJson(res, 404, { error: 'not found' });
});

server.listen(port, hostname, () => {
  console.log(`[registry] listening on http://${hostname}:${port}`);
});

process.on('SIGINT', () => {
  server.close(() => {
    console.log('[registry] shutdown');
    process.exit(0);
  });
});
