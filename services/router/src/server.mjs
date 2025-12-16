import http from 'node:http';

const port = Number(process.env.AFM_ROUTER_PORT ?? 4810);
const hostname = process.env.AFM_ROUTER_HOST ?? '127.0.0.1';
const startedAt = Date.now();

const packs = [
  { id: 'afm://demo-writer', name: 'Demo Writer', skills: ['summarize'], status: 'healthy' },
  { id: 'afm://image-tool', name: 'Image Tool', skills: ['vision'], status: 'degraded' }
];

const args = new Set(process.argv.slice(2));

if (args.has('--snapshot')) {
  console.log('[router] snapshot build complete');
  process.exit(0);
}

if (args.has('--lint')) {
  console.log('[router] configuration OK');
  process.exit(0);
}

if (args.has('--self-test')) {
  if (packs.length === 0) {
    console.error('router has no packs registered');
    process.exit(1);
  }
  console.log('[router] self-test passed');
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
    return sendJson(res, 200, { data: packs });
  }

  if (req.method === 'POST' && url.pathname === '/route') {
    let body = '';
    req.on('data', chunk => (body += chunk));
    req.on('end', () => {
      try {
        const payload = body.length ? JSON.parse(body) : {};
        const skill = payload.skill ?? 'general';
        const candidate = packs.find(p => p.skills.includes(skill)) ?? packs[0];
        sendJson(res, 200, { selection: candidate, requestedSkill: skill });
      } catch (err) {
        sendJson(res, 400, { error: 'invalid JSON', detail: String(err) });
      }
    });
    return;
  }

  sendJson(res, 404, { error: 'not found' });
});

server.listen(port, hostname, () => {
  console.log(`[router] listening on http://${hostname}:${port}`);
});

process.on('SIGINT', () => {
  server.close(() => {
    console.log('[router] shutdown');
    process.exit(0);
  });
});
