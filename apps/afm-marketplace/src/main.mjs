import http from 'node:http';

const DEFAULT_PROMPT_TEMPLATE = '{{system}}\n\nContext:\n{{context}}\n\nUser:\n{{prompt}}';
const DEFAULT_PRICE_PER_1K = 0;

export function createMarketplaceState(options = {}) {
  const now = options.now ?? (() => new Date());
  const state = {
    startedAt: now(),
    ownerID: normalizeString(options.ownerID) ?? 'local-user',
    jobs: new Map(),
    packs: new Map(),
    experts: new Map(),
    now
  };

  for (const pack of options.seedPacks ?? []) {
    state.packs.set(pack.runner_id, pack);
  }
  for (const expert of options.seedExperts ?? []) {
    state.experts.set(expert.id, expert);
  }

  return state;
}

export function renderMarketplace(state = createMarketplaceState()) {
  return {
    status: 'ready',
    packs: state.packs.size,
    experts: state.experts.size,
    trainingJobs: state.jobs.size,
    message: 'Local AFM marketplace service is ready'
  };
}

export function createTrainingJob(state, payload) {
  const request = normalizeTrainingRequest(payload);
  const stable = digestHex([
    request.displayName,
    request.objective,
    request.datasetSummary,
    request.policy.baseModelID,
    request.policy.method,
    request.policy.privacyMode,
    request.policy.domainTags.join(',')
  ].join('|'));
  const createdAt = state.now().toISOString();
  const localAdapterID = `afm-local-${stable}`;
  const outputRunnerID = `${localAdapterID}@v1`;
  const publishReadiness = publishReadinessFor(request.policy);
  const publishStatus = publishReadiness === 'needsAttestation' || publishReadiness === 'readyForAFMarket'
    ? 'draft'
    : 'blocked';
  const status = publishStatus === 'blocked' && request.policy.publishToAFMarket
    ? 'publishBlocked'
    : 'readyForLocalUse';
  const runnerPack = buildRunnerPack({
    request,
    stable,
    outputRunnerID,
    localAdapterID,
    ownerID: state.ownerID,
    createdAtMillis: Date.parse(createdAt)
  });
  const peerExpert = buildPeerExpert({
    request,
    stable,
    outputRunnerID,
    localAdapterID,
    createdAt
  });
  const job = {
    id: `train-${stable}`,
    request,
    status,
    publishReadiness,
    publishStatus,
    progress: 1,
    localAdapterID,
    outputRunnerID,
    artifactBundleURL: `local://afm-marketplace/artifacts/${outputRunnerID}.json`,
    manifestHash: runnerPack.hashes.manifest,
    createdAt,
    updatedAt: createdAt,
    trainingSummary: `Prepared ${methodTitle(request.policy.method).toLowerCase()} artifact from ${request.sampleCount} approved example${request.sampleCount === 1 ? '' : 's'} for ${request.policy.baseModelID}.`,
    adapterStatus: adapterStatusFor(request.policy),
    runnerPack,
    peerExpert
  };

  state.jobs.set(job.id, job);
  return job;
}

export function publishTrainingJob(state, id) {
  const job = state.jobs.get(id);
  if (!job) {
    const error = new Error('training job not found');
    error.statusCode = 404;
    throw error;
  }

  if (job.publishStatus === 'blocked') {
    const error = new Error('training job is not publishable with its current policy');
    error.statusCode = 409;
    throw error;
  }

  const updatedAt = state.now().toISOString();
  const published = {
    ...job,
    status: 'publishReady',
    publishReadiness: 'readyForAFMarket',
    publishStatus: 'published',
    updatedAt,
    runnerPack: {
      ...job.runnerPack,
      status: 'marketplace',
      created_at: Date.parse(updatedAt)
    },
    peerExpert: {
      ...job.peerExpert,
      updatedAt,
      attestation: job.peerExpert.attestation ?? 'local-adapter-attested'
    }
  };
  state.jobs.set(id, published);
  state.packs.set(published.runnerPack.runner_id, published.runnerPack);
  state.experts.set(published.peerExpert.id, published.peerExpert);
  return published;
}

export function createRequestHandler(state = createMarketplaceState()) {
  return async (req, res) => {
    const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);

    try {
      if (req.method === 'GET' && url.pathname === '/health') {
        return sendJson(res, 200, {
          ok: true,
          uptimeMs: Date.now() - state.startedAt.getTime(),
          packs: state.packs.size,
          experts: state.experts.size,
          trainingJobs: state.jobs.size
        });
      }

      if (req.method === 'GET' && url.pathname === '/api/packs') {
        return sendJson(res, 200, { packs: Array.from(state.packs.values()) });
      }

      if (req.method === 'GET' && url.pathname === '/api/experts') {
        return sendJson(res, 200, { experts: Array.from(state.experts.values()) });
      }

      if (req.method === 'GET' && url.pathname === '/api/training-jobs') {
        return sendJson(res, 200, { jobs: Array.from(state.jobs.values()) });
      }

      if (req.method === 'POST' && url.pathname === '/api/training-jobs') {
        const job = createTrainingJob(state, await readJson(req));
        return sendJson(res, 201, { job });
      }

      const trainingMatch = url.pathname.match(/^\/api\/training-jobs\/([^/]+)$/);
      if (req.method === 'GET' && trainingMatch) {
        const job = state.jobs.get(decodeURIComponent(trainingMatch[1]));
        return job
          ? sendJson(res, 200, { job })
          : sendJson(res, 404, { error: 'training job not found' });
      }

      const publishMatch = url.pathname.match(/^\/api\/training-jobs\/([^/]+)\/publish$/);
      if (req.method === 'POST' && publishMatch) {
        const job = publishTrainingJob(state, decodeURIComponent(publishMatch[1]));
        return sendJson(res, 200, { job, pack: job.runnerPack, expert: job.peerExpert });
      }

      const artifactMatch = url.pathname.match(/^\/api\/artifacts\/([^/]+)$/);
      if (req.method === 'GET' && artifactMatch) {
        const runnerID = decodeURIComponent(artifactMatch[1]).replace(/\.json$/, '');
        const job = Array.from(state.jobs.values()).find(value => value.outputRunnerID === runnerID);
        return job
          ? sendJson(res, 200, artifactManifest(job))
          : sendJson(res, 404, { error: 'artifact not found' });
      }

      return sendJson(res, 404, { error: 'not found' });
    } catch (err) {
      return sendJson(res, err.statusCode ?? 400, {
        error: 'invalid marketplace request',
        detail: String(err.message ?? err)
      });
    }
  };
}

export function startMarketplaceServer(options = {}) {
  const state = options.state ?? createMarketplaceState(options);
  const port = Number(options.port ?? process.env.AFM_MARKETPLACE_PORT ?? 4850);
  const hostname = options.hostname ?? process.env.AFM_MARKETPLACE_HOST ?? '127.0.0.1';
  const server = http.createServer(createRequestHandler(state));

  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, hostname, () => {
      server.off('error', reject);
      resolve({
        server,
        state,
        url: `http://${hostname}:${server.address().port}`
      });
    });
  });
}

export async function selfTest() {
  const state = createMarketplaceState({ now: fixedClock() });
  const job = createTrainingJob(state, demoTrainingRequest());
  if (job.publishStatus !== 'draft' || job.runnerPack.runner_id !== job.outputRunnerID) {
    throw new Error('training job artifact contract failed');
  }
  const published = publishTrainingJob(state, job.id);
  if (!state.packs.has(published.outputRunnerID) || !state.experts.has(published.outputRunnerID)) {
    throw new Error('published marketplace indexes missing local expert');
  }
  return renderMarketplace(state);
}

function buildRunnerPack({ request, stable, outputRunnerID, localAdapterID, ownerID, createdAtMillis }) {
  const domainTags = request.policy.domainTags.length ? request.policy.domainTags : ['local-expert'];
  const manifestHash = `sha256:${digestHex(`${stable}|manifest`)}`;
  const adapterHash = `sha256:${digestHex(`${stable}|adapter`)}`;
  const bundleHash = `sha256:${digestHex(`${stable}|bundle`)}`;
  return {
    runner_id: outputRunnerID,
    afm: {
      model_id: request.policy.baseModelID
    },
    prompting: {
      system: `You are ${request.displayName}. ${request.objective}`,
      template: DEFAULT_PROMPT_TEMPLATE,
      params: {
        temperature: 0.2,
        top_p: 0.9,
        max_tokens: 900
      }
    },
    policy: {
      allowed_domains: domainTags,
      max_context: Math.min(160000, Math.max(4096, request.policy.maxTrainingExamples * 256))
    },
    royalties: {
      creator_bps: request.policy.publishToAFMarket ? 500 : 0,
      data_bps: request.policy.privacyMode === 'publishable' ? 100 : 0
    },
    attestation: [
      `method:${request.policy.method}`,
      `privacy:${request.policy.privacyMode}`,
      `examples:${request.sampleCount}`
    ],
    capability_vector: capabilityVectorFor(domainTags),
    hashes: {
      manifest: manifestHash,
      adapter: adapterHash,
      bundle: bundleHash
    },
    bundle_url: `local://afm-marketplace/artifacts/${outputRunnerID}.json`,
    signature: `local-dev:${digestHex(`${stable}|signature`)}`,
    runner_root: `fnv1a64:${stable}`,
    owner_id: ownerID,
    created_at: createdAtMillis,
    local_adapter_id: localAdapterID,
    status: 'draft'
  };
}

function buildPeerExpert({ request, stable, outputRunnerID, localAdapterID, createdAt }) {
  return {
    id: outputRunnerID,
    name: request.displayName,
    payoutAddr: null,
    nodePub: `local-node-${stable.slice(0, 16)}`,
    capability: capabilityVectorFor(request.policy.domainTags),
    pricePer1k: DEFAULT_PRICE_PER_1K,
    latencyP50: 5,
    tags: request.policy.domainTags,
    baseModel: request.policy.baseModelID,
    coverage: 1,
    reputation: 0,
    stake: 0,
    attestation: `local-adapter:${localAdapterID}`,
    ingestUrl: `local://afm-marketplace/a2a/${outputRunnerID}`,
    profileSig: `local-profile:${digestHex(`${stable}|profile`)}`,
    createdAt,
    updatedAt: createdAt
  };
}

function artifactManifest(job) {
  return {
    schema: 'dBrowser.afm.local-adapter.v1',
    jobID: job.id,
    runnerID: job.outputRunnerID,
    localAdapterID: job.localAdapterID,
    manifestHash: job.manifestHash,
    request: job.request,
    runnerPack: job.runnerPack,
    peerExpert: job.peerExpert,
    trainingSummary: job.trainingSummary,
    adapterStatus: job.adapterStatus
  };
}

function normalizeTrainingRequest(payload) {
  const displayName = requireString(payload.displayName, 'displayName');
  const objective = normalizeString(payload.objective) ?? 'Answer questions from approved local examples.';
  const datasetSummary = normalizeString(payload.datasetSummary) ?? 'Approved local examples.';
  const sampleCount = Math.max(0, Number.isFinite(Number(payload.sampleCount)) ? Math.floor(Number(payload.sampleCount)) : 0);
  const policy = normalizePolicy(payload.policy ?? {});
  return {
    displayName,
    objective,
    datasetSummary,
    sampleCount,
    policy
  };
}

function normalizePolicy(policy) {
  const method = enumValue(policy.method, ['profileAdapter', 'loraAdapter', 'fullFineTune'], 'profileAdapter');
  const privacyMode = enumValue(policy.privacyMode, ['localOnly', 'redactedA2A', 'publishable'], 'localOnly');
  const tags = Array.isArray(policy.domainTags)
    ? unique(policy.domainTags.map(value => normalizeString(value)?.toLowerCase()).filter(Boolean))
    : [];
  return {
    baseModelID: normalizeString(policy.baseModelID) ?? 'apple.foundation-model.local',
    method,
    privacyMode,
    allowA2A: Boolean(policy.allowA2A),
    publishToAFMarket: Boolean(policy.publishToAFMarket),
    maxTrainingExamples: Math.max(1, Number.isFinite(Number(policy.maxTrainingExamples)) ? Math.floor(Number(policy.maxTrainingExamples)) : 500),
    domainTags: tags
  };
}

function adapterStatusFor(policy) {
  const method = methodTitle(policy.method);
  if (policy.method === 'fullFineTune') {
    return `${method} artifact prepared as a local deterministic adapter manifest. Production Apple Foundation Model weight export is not configured.`;
  }
  return `${method} artifact is ready for local use and marketplace publishing. Production Apple Foundation Model weight export remains a future adapter.`;
}

function publishReadinessFor(policy) {
  if (!policy.publishToAFMarket) {
    return 'localOnly';
  }
  if (!policy.allowA2A || policy.privacyMode === 'localOnly') {
    return 'needsEvaluation';
  }
  return 'needsAttestation';
}

function capabilityVectorFor(tags) {
  const seed = digestInt(tags.join('|') || 'local-expert');
  return [
    roundVector((seed & 0xff) / 255),
    roundVector(((seed >> 8) & 0xff) / 255),
    roundVector(((seed >> 16) & 0xff) / 255)
  ];
}

function methodTitle(method) {
  switch (method) {
    case 'loraAdapter':
      return 'LoRA adapter';
    case 'fullFineTune':
      return 'Full fine-tune';
    default:
      return 'Profile adapter';
  }
}

function demoTrainingRequest() {
  return {
    displayName: 'Local Travel Policy Expert',
    objective: 'Answer travel-policy questions from approved local examples.',
    datasetSummary: 'Redacted examples from travel policy pages and user-approved notes.',
    sampleCount: 42,
    policy: {
      baseModelID: 'apple.foundation-model.local',
      method: 'profileAdapter',
      privacyMode: 'redactedA2A',
      allowA2A: true,
      publishToAFMarket: true,
      maxTrainingExamples: 500,
      domainTags: ['travel', 'policy', 'travel']
    }
  };
}

function fixedClock() {
  const fixed = new Date('2026-01-01T00:00:00.000Z');
  return () => fixed;
}

function enumValue(value, allowed, fallback) {
  return allowed.includes(value) ? value : fallback;
}

function unique(values) {
  return Array.from(new Set(values));
}

function normalizeString(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function requireString(value, fieldName) {
  const normalized = normalizeString(value);
  if (!normalized) {
    const error = new Error(`${fieldName} is required`);
    error.statusCode = 400;
    throw error;
  }
  return normalized;
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => {
      body += chunk;
      if (body.length > 1_000_000) {
        const error = new Error('request body too large');
        error.statusCode = 413;
        reject(error);
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
        const error = new Error(`invalid JSON: ${err.message}`);
        error.statusCode = 400;
        reject(error);
      }
    });
    req.on('error', reject);
  });
}

function sendJson(res, status, payload) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload, null, 2));
}

function roundVector(value) {
  return Math.round(value * 1000) / 1000;
}

function digestHex(input) {
  return digestInt(input).toString(16).padStart(8, '0');
}

function digestInt(input) {
  let hash = 0x811c9dc5;
  for (let index = 0; index < input.length; index += 1) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}
