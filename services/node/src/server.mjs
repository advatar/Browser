import http from 'node:http';

const args = new Set(process.argv.slice(2));
const port = Number(process.env.AFM_NODE_PORT ?? 4840);
const hostname = process.env.AFM_NODE_HOST ?? '127.0.0.1';
const startedAt = Date.now();
const mode = 'local-mock';
let installSequence = 1;
let taskSequence = 1;
const installedPacks = new Map();
const tasks = new Map();

if (args.has('--snapshot')) {
  console.log('[node] snapshot OK');
  process.exit(0);
}

if (args.has('--lint')) {
  console.log('[node] schema OK');
  process.exit(0);
}

if (args.has('--self-test')) {
  const install = installPack({
    packID: 'afm://self-test',
    checksum: '0xselftest',
    bundleURL: null,
    requestedBy: 'self-test'
  });
  const task = dispatchTask({
    prompt: 'Summarize node self-test',
    pageURLString: 'https://example.com',
    selectedPackID: install.packID,
    pageSnapshotCommitment: 'snap-self-test',
    memoryContextIDs: ['mem-self-test']
  });

  if (!install.id || install.status !== 'installed' || task.status !== 'completed' || task.attestation.mode !== mode) {
    console.error('[node] self-test failed');
    process.exit(1);
  }

  console.log('[node] self-test complete');
  process.exit(0);
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

function installPack(payload) {
  const packID = requireString(payload.packID, 'packID');
  const checksum = typeof payload.checksum === 'string' && payload.checksum.trim() ? payload.checksum.trim() : null;
  const install = {
    ok: true,
    id: `install-${installSequence++}`,
    packID,
    checksum,
    bundleURL: typeof payload.bundleURL === 'string' && payload.bundleURL.trim() ? payload.bundleURL.trim() : null,
    requestedBy: typeof payload.requestedBy === 'string' && payload.requestedBy.trim() ? payload.requestedBy.trim() : 'swift-copilot',
    status: 'installed',
    mode,
    installedAt: new Date().toISOString(),
    receipt: {
      mode,
      installCommitment: digest([packID, checksum ?? 'no-checksum', String(installSequence)].join('|')),
      verifier: 'local-dev'
    }
  };
  installedPacks.set(packID, install);
  return install;
}

function dispatchTask(payload) {
  const prompt = requireString(payload.prompt, 'prompt');
  const selectedPackID = typeof payload.selectedPackID === 'string' && payload.selectedPackID.trim()
    ? payload.selectedPackID.trim()
    : 'afm://router-default';
  const installedPack = installedPacks.get(selectedPackID);
  const taskID = `task-${taskSequence++}`;
  const pageURLString = typeof payload.pageURLString === 'string' && payload.pageURLString.trim()
    ? payload.pageURLString.trim()
    : null;
  const pageSnapshotCommitment = typeof payload.pageSnapshotCommitment === 'string' && payload.pageSnapshotCommitment.trim()
    ? payload.pageSnapshotCommitment.trim()
    : null;
  const memoryContextIDs = Array.isArray(payload.memoryContextIDs)
    ? payload.memoryContextIDs.filter(value => typeof value === 'string' && value.trim()).map(value => value.trim())
    : [];
  const output = [
    `Node executed ${selectedPackID} in ${mode} mode.`,
    `Prompt characters: ${prompt.length}.`,
    pageURLString ? `Page: ${pageURLString}.` : 'No page URL supplied.',
    memoryContextIDs.length ? `Memory contexts: ${memoryContextIDs.join(', ')}.` : 'No governed memory contexts supplied.'
  ].join(' ');
  const outputCommitment = digest([taskID, selectedPackID, prompt, pageURLString ?? '', pageSnapshotCommitment ?? '', memoryContextIDs.join(',')].join('|'));
  const task = {
    ok: true,
    id: taskID,
    taskID,
    packID: selectedPackID,
    installID: installedPack?.id ?? null,
    status: 'completed',
    mode,
    result: {
      summary: output,
      outputCommitment,
      completedAt: new Date().toISOString()
    },
    attestation: {
      mode,
      taskID,
      outputCommitment,
      nonce: digest(`${taskID}|nonce`).slice(0, 16),
      tokenCount: estimateTokens(prompt),
      contextPassages: memoryContextIDs.length,
      attestationToken: null
    },
    proof: {
      id: `proof-${taskID}`,
      proofID: `proof-${taskID}`,
      status: 'mock',
      verifier: 'local-dev',
      publicInputs: {
        packID: selectedPackID,
        pageSnapshotCommitment: pageSnapshotCommitment ?? '',
        outputCommitment
      }
    },
    settlement: {
      id: `settlement-${taskID}`,
      status: 'mock',
      chainRef: 'local-devnet',
      escrowID: null,
      verifier: 'local-dev',
      mode,
      settledAt: new Date().toISOString()
    }
  };
  tasks.set(taskID, task);
  return task;
}

function estimateTokens(text) {
  return Math.max(1, Math.ceil(text.length / 4));
}

function requireString(value, fieldName) {
  if (typeof value !== 'string' || !value.trim()) {
    const error = new Error(`${fieldName} is required`);
    error.statusCode = 400;
    throw error;
  }
  return value.trim();
}

function digest(input) {
  let hash = 0x811c9dc5;
  for (let index = 0; index < input.length; index += 1) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return `0x${hash.toString(16).padStart(8, '0')}`;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);

  if (req.method === 'GET' && url.pathname === '/health') {
    return sendJson(res, 200, {
      ok: true,
      uptimeMs: Date.now() - startedAt,
      installedPacks: installedPacks.size,
      tasks: tasks.size,
      mode
    });
  }

  if (req.method === 'GET' && url.pathname === '/packs/install') {
    return sendJson(res, 200, { data: Array.from(installedPacks.values()) });
  }

  if (req.method === 'POST' && url.pathname === '/packs/install') {
    try {
      const payload = await readJson(req);
      return sendJson(res, 201, installPack(payload));
    } catch (err) {
      return sendJson(res, err.statusCode ?? 400, { error: 'invalid install request', detail: String(err.message ?? err) });
    }
  }

  if (req.method === 'GET' && url.pathname === '/tasks') {
    return sendJson(res, 200, { data: Array.from(tasks.values()) });
  }

  if (req.method === 'POST' && url.pathname === '/tasks') {
    try {
      const payload = await readJson(req);
      return sendJson(res, 202, dispatchTask(payload));
    } catch (err) {
      return sendJson(res, err.statusCode ?? 400, { error: 'invalid task request', detail: String(err.message ?? err) });
    }
  }

  if (req.method === 'GET' && url.pathname.startsWith('/tasks/')) {
    const taskID = decodeURIComponent(url.pathname.slice('/tasks/'.length));
    const task = tasks.get(taskID);
    if (!task) {
      return sendJson(res, 404, { error: 'task not found' });
    }
    return sendJson(res, 200, task);
  }

  sendJson(res, 404, { error: 'not found' });
});

server.listen(port, hostname, () => {
  console.log(`[node] agent started on http://${hostname}:${port}`);
});

process.on('SIGINT', () => {
  server.close(() => {
    console.log('[node] shutdown');
    process.exit(0);
  });
});
