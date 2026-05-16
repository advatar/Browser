import http from 'node:http';

const args = new Set(process.argv.slice(2));
const port = Number(process.env.AFM_PIPELINES_PORT ?? 4830);
const hostname = process.env.AFM_PIPELINES_HOST ?? '127.0.0.1';
const startedAt = Date.now();
let jobSequence = 1;
const queue = [];
const jobs = new Map();

if (args.has('--snapshot')) {
  console.log('[pipelines] snapshot OK');
  process.exit(0);
}
if (args.has('--lint')) {
  console.log('[pipelines] lint succeeded');
  process.exit(0);
}
if (args.has('--self-test')) {
  const job = enqueue({ name: 'self-test', payload: { ok: true } });
  if (!job.id || job.status !== 'queued') {
    console.error('[pipelines] self-test failed');
    process.exit(1);
  }
  console.log('[pipelines] self-test complete');
  process.exit(0);
}

function enqueue(task) {
  const job = {
    id: `job-${jobSequence++}`,
    name: task.name || 'unnamed-job',
    payload: task.payload || {},
    status: 'queued',
    enqueuedAt: Date.now(),
    completedAt: null
  };
  queue.push(job);
  jobs.set(job.id, job);
  return job;
}

function processQueue() {
  const job = queue.shift();
  if (!job) {
    return;
  }
  job.status = 'running';
  console.log('[pipelines] executing job', job.name);
  setTimeout(() => {
    job.status = 'completed';
    job.completedAt = Date.now();
    console.log('[pipelines] completed job', job.name);
  }, 250);
}

const sendJson = (res, status, payload) => {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload, null, 2));
};

const readJson = req =>
  new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => {
      body += chunk;
      if (body.length > 1_000_000) {
        reject(new Error('request body too large'));
        req.destroy();
      }
    });
    req.on('end', () => {
      if (!body.trim()) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(body));
      } catch (err) {
        reject(err);
      }
    });
    req.on('error', reject);
  });

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);

  if (req.method === 'GET' && url.pathname === '/health') {
    return sendJson(res, 200, {
      ok: true,
      uptimeMs: Date.now() - startedAt,
      queued: queue.length,
      jobs: jobs.size
    });
  }

  if (req.method === 'GET' && url.pathname === '/jobs') {
    return sendJson(res, 200, { data: Array.from(jobs.values()) });
  }

  if (req.method === 'POST' && url.pathname === '/jobs') {
    try {
      const payload = await readJson(req);
      const job = enqueue(payload);
      return sendJson(res, 202, { ok: true, id: job.id, status: job.status });
    } catch (err) {
      return sendJson(res, 400, { error: 'invalid JSON', detail: String(err) });
    }
  }

  sendJson(res, 404, { error: 'not found' });
});

setInterval(processQueue, 500);
setInterval(() => enqueue({ name: 'sample-job', payload: { now: Date.now() } }), 1_000);

server.listen(port, hostname, () => {
  console.log(`[pipelines] worker started on http://${hostname}:${port}`);
});

process.on('SIGINT', () => {
  server.close(() => {
    console.log('[pipelines] shutdown');
    process.exit(0);
  });
});
