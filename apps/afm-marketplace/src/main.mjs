import http from 'node:http';
import { createHash, randomUUID } from 'node:crypto';

const DEFAULT_PROMPT_TEMPLATE = '{{system}}\n\nContext:\n{{context}}\n\nUser:\n{{prompt}}';
const DEFAULT_PUBLIC_BASE_URL = 'http://127.0.0.1:4850';
const DEFAULT_QUOTE_TTL_MS = 5 * 60 * 1000;
const PRICING_SCHEMA = 'afm.marketplace.pricing.v1';
const RECEIPT_SCHEMA = 'afm.marketplace.inference-receipt.v1';

export function createMarketplaceState(options = {}) {
  const now = options.now ?? (() => new Date());
  const state = {
    startedAt: now(),
    ownerID: normalizeString(options.ownerID) ?? 'local-user',
    jobs: new Map(),
    packs: new Map(),
    experts: new Map(),
    quotes: new Map(),
    inferences: new Map(),
    receipts: new Map(),
    idempotency: new Map(),
    publicBaseURL: normalizePublicBaseURL(options.publicBaseURL ?? DEFAULT_PUBLIC_BASE_URL),
    quoteTTLMS: positiveInteger(options.quoteTTLMS, DEFAULT_QUOTE_TTL_MS, 'quoteTTLMS'),
    inferenceExecutor: options.inferenceExecutor ?? null,
    tokenEstimator: options.tokenEstimator ?? null,
    paymentProcessor: options.paymentProcessor ?? null,
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
    quotes: state.quotes.size,
    inferences: state.inferences.size,
    receipts: state.receipts.size,
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
    createdAt,
    publicBaseURL: state.publicBaseURL
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

export function createInferenceQuote(state, runnerID, payload) {
  const { pack, expert } = publishedRunner(state, runnerID);
  const request = normalizeInferenceRequest(payload, pack);
  const createdAt = state.now();
  const expiresAt = new Date(createdAt.getTime() + state.quoteTTLMS);
  const renderedPrompt = renderRunnerPrompt(pack, request);
  const pricing = pricingForExpert(expert);
  const tokenEstimate = quoteTokenEstimate(state, pricing, renderedPrompt, pack);
  const promptTokensEstimated = tokenEstimate.promptTokens;
  if (promptTokensEstimated + request.parameters.maxTokens > pack.policy.max_context) {
    throw marketplaceError(
      'CONTEXT_TOKEN_CAP_EXCEEDED',
      'authoritative prompt usage and output cap exceed the runner context policy',
      422
    );
  }
  const maxBillableTokens = promptTokensEstimated + request.parameters.maxTokens;
  const maxAmountMinorUnits = calculateCharge(pricing, maxBillableTokens);
  const royaltyTerms = normalizeRoyaltyTerms(pack.royalties);
  const id = `quote-${randomUUID()}`;
  const inputCommitment = commitmentFor({ prompt: request.prompt, context: request.context });
  const parametersCommitment = commitmentFor(request.parameters);
  const profileCommitment = expertProfileCommitment(expert);
  const manifestCommitment = pack.hashes?.manifest ?? commitmentFor(pack);
  const quoteBinding = {
    id,
    runnerID,
    expertID: expert.id,
    modelID: pack.afm.model_id,
    profileCommitment,
    manifestCommitment,
    inputCommitment,
    parametersCommitment,
    promptTokensEstimated,
    quoteTokenizerID: tokenEstimate.tokenizerID,
    promptTokensAuthoritative: tokenEstimate.authoritative,
    maxBillableTokens,
    pricingRevision: pricing.revision,
    rateMinorUnitsPer1K: pricing.rateMinorUnitsPer1K,
    maxAmountMinorUnits,
    asset: pricing.asset,
    network: pricing.network,
    payTo: pricing.payTo,
    royaltyTerms,
    createdAt: createdAt.toISOString(),
    expiresAt: expiresAt.toISOString()
  };
  const requirementHash = commitmentFor(quoteBinding);
  const paymentRequirement = pricing.mode === 'metered'
    ? {
        scheme: 'x402',
        id: `afm-inference-${id}`,
        resourceURLString: `${expert.ingestUrl}/inferences`,
        amountMinorUnits: maxAmountMinorUnits,
        asset: pricing.asset,
        network: pricing.network,
        payTo: pricing.payTo,
        expiresAt: expiresAt.toISOString(),
        requirementHash
      }
    : null;
  const quote = {
    schema: 'afm.marketplace.inference-quote.v1',
    id,
    status: 'open',
    runnerID,
    expertID: expert.id,
    modelID: pack.afm.model_id,
    profileCommitment,
    manifestCommitment,
    inputCommitment,
    parametersCommitment,
    promptTokensEstimated,
    quoteTokenizerID: tokenEstimate.tokenizerID,
    promptTokensAuthoritative: tokenEstimate.authoritative,
    maxOutputTokens: request.parameters.maxTokens,
    maxBillableTokens,
    pricing,
    royaltyTerms,
    maxAmountMinorUnits,
    requirementHash,
    paymentRequirement,
    createdAt: createdAt.toISOString(),
    expiresAt: expiresAt.toISOString()
  };
  state.quotes.set(id, quote);
  return quote;
}

export async function executeInference(state, runnerID, payload, idempotencyKey) {
  const normalizedKey = requireIdempotencyKey(idempotencyKey);
  const quoteID = requireString(payload?.quoteID ?? payload?.quote_id, 'quoteID');
  const quote = state.quotes.get(quoteID);
  if (!quote || quote.runnerID !== runnerID) {
    throw marketplaceError('QUOTE_NOT_FOUND', 'inference quote not found', 404);
  }
  const { pack, expert } = publishedRunner(state, runnerID);
  const request = normalizeInferenceRequest(payload, pack);
  const inputCommitment = commitmentFor({ prompt: request.prompt, context: request.context });
  const paymentCommitment = payload?.payment == null ? null : commitmentFor(payload.payment);
  const requestCommitment = commitmentFor({
    runnerID,
    quoteID,
    inputCommitment,
    parameters: request.parameters,
    paymentCommitment
  });
  const existing = state.idempotency.get(normalizedKey);
  if (existing) {
    if (existing.requestCommitment !== requestCommitment) {
      throw marketplaceError('IDEMPOTENCY_CONFLICT', 'idempotency key was already used for a different request', 409);
    }
    if (existing.terminalError) {
      throw marketplaceError(
        existing.terminalError.code,
        existing.terminalError.message,
        existing.terminalError.statusCode,
        existing.terminalError.retryable,
        { inferenceID: existing.inferenceID }
      );
    }
    return state.inferences.get(existing.inferenceID);
  }

  validateQuoteForExecution(state, quote, expert, request, inputCommitment);
  const executor = inferenceExecutorFor(state);
  const pricing = quote.pricing;
  if (pricing.mode === 'metered') {
    if (!payload?.payment) {
      throw marketplaceError('PAYMENT_REQUIRED', 'metered inference requires payment authorization', 402, false, {
        quoteID: quote.id,
        paymentRequirement: quote.paymentRequirement
      });
    }
    if (payload.payment.requirementHash !== quote.requirementHash) {
      throw marketplaceError('PAYMENT_REQUIREMENT_MISMATCH', 'payment is not bound to this inference quote', 402);
    }
    paymentProcessorFor(state);
  }

  const createdAt = state.now().toISOString();
  const inference = {
    id: `inference-${randomUUID()}`,
    status: pricing.mode === 'metered' ? 'authorizing' : 'running',
    runnerID,
    expertID: expert.id,
    modelID: pack.afm.model_id,
    quoteID: quote.id,
    requirementHash: quote.requirementHash,
    idempotencyCommitment: commitmentFor({ key: normalizedKey }),
    inputCommitment,
    parametersCommitment: quote.parametersCommitment,
    pricingRevision: pricing.revision,
    createdAt,
    completedAt: null,
    usage: null,
    charge: null,
    output: null,
    receiptID: null,
    error: null
  };
  state.inferences.set(inference.id, inference);
  state.idempotency.set(normalizedKey, { requestCommitment, inferenceID: inference.id });
  quote.status = 'processing';

  let authorization = null;
  try {
    if (pricing.mode === 'metered') {
      authorization = await authorizePayment(state, quote, payload.payment, inference);
      ensureQuoteNotExpired(state, quote);
      inference.status = 'running';
    }

    const execution = await executeWithProvider(executor, {
      inferenceID: inference.id,
      runnerID,
      expertID: expert.id,
      modelID: pack.afm.model_id,
      prompt: request.prompt,
      context: request.context,
      renderedPrompt: renderRunnerPrompt(pack, request),
      parameters: request.parameters,
      inputCommitment,
      manifestCommitment: quote.manifestCommitment,
      profileCommitment: quote.profileCommitment
    });
    const usage = normalizeAuthoritativeUsage(execution?.usage);
    if (usage.completionTokens > quote.maxOutputTokens) {
      throw marketplaceError('OUTPUT_TOKEN_CAP_EXCEEDED', 'runtime completion usage exceeded the quoted output cap', 502);
    }
    if (
      pricing.mode === 'metered'
      && (usage.promptTokens !== quote.promptTokensEstimated || usage.tokenizerID !== quote.quoteTokenizerID)
    ) {
      throw marketplaceError('PROMPT_USAGE_MISMATCH', 'runtime prompt usage does not match the authoritative quote tokenizer', 502);
    }
    if (usage.totalTokens > quote.maxBillableTokens) {
      throw marketplaceError('USAGE_CAP_EXCEEDED', 'runtime usage exceeded the quoted token cap', 502);
    }
    const chargedAmountMinorUnits = calculateCharge(pricing, usage.totalTokens);
    if (chargedAmountMinorUnits > quote.maxAmountMinorUnits) {
      throw marketplaceError('CHARGE_EXCEEDS_QUOTE', 'runtime charge exceeded the authorized quote', 502);
    }
    const outputText = normalizeString(execution?.text);
    if (!outputText) {
      throw marketplaceError('EXECUTOR_RESPONSE_INVALID', 'executor did not return output text', 502);
    }
    const outputCommitment = commitmentFor({ text: outputText });
    const royaltySplit = allocateRoyalties(chargedAmountMinorUnits, quote.royaltyTerms);
    const publicUsage = privacySafeUsage(usage);
    const settlement = pricing.mode === 'metered'
      ? await settlePayment(state, quote, authorization, chargedAmountMinorUnits, inference, {
          usage: publicUsage,
          outputCommitment,
          royaltySplit
        })
      : {
          status: 'not-required',
          settlementID: null,
          transactionReference: null,
          authorizationRemainderMinorUnits: 0,
          usageCommitment: null,
          royaltySplitCommitment: null
        };
    const receipt = {
      schema: RECEIPT_SCHEMA,
      id: `receipt-${randomUUID()}`,
      status: pricing.mode === 'metered' ? 'settled' : 'free',
      inferenceID: inference.id,
      quoteID: quote.id,
      requirementHash: quote.requirementHash,
      idempotencyCommitment: inference.idempotencyCommitment,
      runnerID,
      expertID: expert.id,
      modelID: pack.afm.model_id,
      profileCommitment: quote.profileCommitment,
      manifestCommitment: quote.manifestCommitment,
      inputCommitment,
      outputCommitment,
      usage: publicUsage,
      pricing: receiptPricing(pricing),
      authorizedAmountMinorUnits: authorization?.authorizedAmountMinorUnits ?? 0,
      chargedAmountMinorUnits,
      authorizationRemainderMinorUnits: settlement.authorizationRemainderMinorUnits,
      royaltySplit,
      payment: {
        authorizationID: authorization?.authorizationID ?? null,
        paymentReference: authorization?.paymentReference ?? null,
        settlementID: settlement.settlementID ?? null,
        transactionReference: settlement.transactionReference ?? null,
        usageCommitment: settlement.usageCommitment,
        royaltySplitCommitment: settlement.royaltySplitCommitment
      },
      runtime: {
        requestCommitment: optionalCommitment(execution?.runtimeRequestID),
        usageAttestationCommitment: publicUsage.usageAttestationCommitment,
        tokenizerID: usage.tokenizerID
      },
      createdAt,
      completedAt: state.now().toISOString()
    };
    receipt.commitment = commitmentFor(receipt);
    state.receipts.set(receipt.id, receipt);
    inference.status = 'completed';
    inference.completedAt = receipt.completedAt;
    inference.usage = publicUsage;
    inference.charge = {
      amountMinorUnits: chargedAmountMinorUnits,
      asset: pricing.asset,
      network: pricing.network,
      payTo: pricing.payTo,
      status: receipt.status
    };
    inference.output = { text: outputText, commitment: outputCommitment };
    inference.receiptID = receipt.id;
    quote.status = 'consumed';
    quote.inferenceID = inference.id;
    return inference;
  } catch (error) {
    const release = authorization
      ? await releasePayment(state, authorization, inference, error)
      : { confirmed: true, releaseReference: null };
    const normalized = normalizeMarketplaceError(error);
    inference.status = 'failed';
    inference.completedAt = state.now().toISOString();
    inference.error = {
      code: normalized.code,
      message: normalized.message,
      retryable: normalized.retryable
    };
    inference.reconciliationRequired = Boolean(authorization && !release.confirmed);
    inference.releaseReferenceCommitment = optionalCommitment(release.releaseReference);
    state.idempotency.get(normalizedKey).terminalError = {
      code: normalized.code,
      message: normalized.message,
      statusCode: normalized.statusCode,
      retryable: normalized.retryable
    };
    quote.status = 'failed';
    quote.inferenceID = inference.id;
    throw marketplaceError(normalized.code, normalized.message, normalized.statusCode, normalized.retryable, {
      ...(normalized.details ?? {}),
      inferenceID: inference.id
    });
  }
}

export function calculateCharge(pricing, totalTokens) {
  const tokens = nonNegativeInteger(totalTokens, 'totalTokens');
  if (pricing.mode === 'free') {
    return 0;
  }
  const rate = positiveInteger(pricing.rateMinorUnitsPer1K, null, 'rateMinorUnitsPer1K');
  const raw = (BigInt(tokens) * BigInt(rate) + 999n) / 1000n;
  const minimum = BigInt(nonNegativeInteger(pricing.minChargeMinorUnits ?? 0, 'minChargeMinorUnits'));
  const amount = raw > minimum ? raw : minimum;
  if (amount > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw marketplaceError('CHARGE_OVERFLOW', 'calculated charge exceeds the safe integer range', 422);
  }
  return Number(amount);
}

export function getProviderSummary(state) {
  const inferenceCounts = { authorizing: 0, running: 0, completed: 0, failed: 0 };
  for (const inference of state.inferences.values()) {
    inferenceCounts[inference.status] = (inferenceCounts[inference.status] ?? 0) + 1;
  }
  const totals = new Map();
  for (const receipt of state.receipts.values()) {
    const key = `${receipt.pricing.asset}|${receipt.pricing.network}`;
    const current = totals.get(key) ?? {
      asset: receipt.pricing.asset,
      network: receipt.pricing.network,
      chargedAmountMinorUnits: 0,
      inferenceCount: 0
    };
    current.chargedAmountMinorUnits += receipt.chargedAmountMinorUnits;
    current.inferenceCount += 1;
    totals.set(key, current);
  }
  return {
    status: 'ready',
    publishedRunners: state.packs.size,
    meteredExperts: Array.from(state.experts.values()).filter(expert => expert.pricing?.mode === 'metered').length,
    openQuotes: Array.from(state.quotes.values()).filter(quote => quote.status === 'open').length,
    inferenceCounts,
    reconciliationRequired: Array.from(state.inferences.values()).filter(inference => inference.reconciliationRequired).length,
    receipts: state.receipts.size,
    totals: Array.from(totals.values())
  };
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
          trainingJobs: state.jobs.size,
          quotes: state.quotes.size,
          inferences: state.inferences.size,
          receipts: state.receipts.size
        });
      }

      if (req.method === 'GET' && url.pathname === '/api/packs') {
        return sendJson(res, 200, { packs: Array.from(state.packs.values()) });
      }

      if (req.method === 'GET' && url.pathname === '/api/experts') {
        return sendJson(res, 200, { experts: Array.from(state.experts.values()) });
      }

      if (req.method === 'GET' && url.pathname === '/api/provider/summary') {
        return sendJson(res, 200, { provider: getProviderSummary(state) });
      }

      const quoteMatch = url.pathname.match(/^\/api\/runners\/([^/]+)\/quotes$/);
      if (req.method === 'POST' && quoteMatch) {
        const quote = createInferenceQuote(
          state,
          decodeURIComponent(quoteMatch[1]),
          await readJson(req)
        );
        return sendJson(res, 201, { quote });
      }

      const inferenceCreateMatch = url.pathname.match(/^\/api\/runners\/([^/]+)\/(?:inferences|tasks)$/);
      if (req.method === 'POST' && inferenceCreateMatch) {
        const inference = await executeInference(
          state,
          decodeURIComponent(inferenceCreateMatch[1]),
          await readJson(req),
          req.headers['idempotency-key']
        );
        const receipt = inference.receiptID ? state.receipts.get(inference.receiptID) : null;
        return sendJson(res, inference.status === 'completed' ? 201 : 202, { inference, receipt });
      }

      const inferenceMatch = url.pathname.match(/^\/api\/inferences\/([^/]+)$/);
      if (req.method === 'GET' && inferenceMatch) {
        const inference = state.inferences.get(decodeURIComponent(inferenceMatch[1]));
        return inference
          ? sendJson(res, 200, { inference })
          : sendJson(res, 404, { error: { code: 'INFERENCE_NOT_FOUND', message: 'inference not found', retryable: false } });
      }

      const receiptMatch = url.pathname.match(/^\/api\/receipts\/([^/]+)$/);
      if (req.method === 'GET' && receiptMatch) {
        const receipt = state.receipts.get(decodeURIComponent(receiptMatch[1]));
        return receipt
          ? sendJson(res, 200, { receipt })
          : sendJson(res, 404, { error: { code: 'RECEIPT_NOT_FOUND', message: 'receipt not found', retryable: false } });
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
      const normalized = normalizeMarketplaceError(err);
      if (normalized.code !== 'MARKETPLACE_REQUEST_INVALID') {
        return sendJson(res, normalized.statusCode, {
          error: {
            code: normalized.code,
            message: normalized.message,
            retryable: normalized.retryable
          },
          ...(normalized.details ?? {})
        });
      }
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
      const address = server.address();
      const activePort = typeof address === 'object' && address ? address.port : port;
      const url = `http://${hostname}:${activePort}`;
      if (options.publicBaseURL == null) {
        state.publicBaseURL = normalizePublicBaseURL(url);
      }
      resolve({
        server,
        state,
        url
      });
    });
  });
}

export async function selfTest() {
  const state = createMarketplaceState({
    now: fixedClock(),
    inferenceExecutor: async () => ({
      text: 'Local marketplace self-test completed.',
      usage: {
        promptTokens: 8,
        completionTokens: 6,
        totalTokens: 14,
        tokenizerID: 'self-test-tokenizer',
        usageAttestation: 'self-test-usage-attestation'
      },
      runtimeRequestID: 'self-test-runtime'
    })
  });
  const job = createTrainingJob(state, demoTrainingRequest());
  if (job.publishStatus !== 'draft' || job.runnerPack.runner_id !== job.outputRunnerID) {
    throw new Error('training job artifact contract failed');
  }
  const published = publishTrainingJob(state, job.id);
  if (!state.packs.has(published.outputRunnerID) || !state.experts.has(published.outputRunnerID)) {
    throw new Error('published marketplace indexes missing local expert');
  }
  const quote = createInferenceQuote(state, published.outputRunnerID, {
    prompt: 'Run the marketplace self-test.'
  });
  const inference = await executeInference(state, published.outputRunnerID, {
    quoteID: quote.id,
    prompt: 'Run the marketplace self-test.'
  }, 'self-test-inference');
  if (inference.status !== 'completed' || !inference.receiptID) {
    throw new Error('marketplace inference self-test failed');
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

function buildPeerExpert({ request, stable, outputRunnerID, localAdapterID, createdAt, publicBaseURL }) {
  const pricing = request.commerce;
  return {
    id: outputRunnerID,
    name: request.displayName,
    payoutAddr: pricing.payTo,
    nodePub: `local-node-${stable.slice(0, 16)}`,
    capability: capabilityVectorFor(request.policy.domainTags),
    pricePer1k: pricing.mode === 'metered'
      ? pricing.rateMinorUnitsPer1K / (10 ** pricing.assetDecimals)
      : 0,
    pricePer1kExact: pricing.mode === 'metered'
      ? decimalMinorUnits(pricing.rateMinorUnitsPer1K, pricing.assetDecimals)
      : '0',
    pricing,
    latencyP50: 5,
    tags: request.policy.domainTags,
    baseModel: request.policy.baseModelID,
    coverage: 1,
    reputation: 0,
    stake: 0,
    attestation: `local-adapter:${localAdapterID}`,
    ingestUrl: `${publicBaseURL}/api/runners/${encodeURIComponent(outputRunnerID)}`,
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
  const commerce = normalizeCommerce(payload.commerce ?? { mode: 'free' });
  return {
    displayName,
    objective,
    datasetSummary,
    sampleCount,
    policy,
    commerce
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

function normalizeCommerce(commerce) {
  const mode = commerce.mode ?? 'free';
  if (!['free', 'metered'].includes(mode)) {
    throw marketplaceError('INVALID_PRICING', 'commerce mode must be free or metered', 422);
  }
  const asset = mode === 'metered'
    ? requireCommerceString(commerce.asset, 'asset')
    : normalizeString(commerce.asset) ?? 'USDC';
  const assetDecimals = nonNegativeInteger(
    mode === 'metered' ? commerce.assetDecimals : commerce.assetDecimals ?? 6,
    'assetDecimals'
  );
  if (assetDecimals > 18) {
    throw marketplaceError('INVALID_PRICING', 'assetDecimals must be between 0 and 18', 422);
  }
  const network = mode === 'metered'
    ? requireCommerceString(commerce.network, 'network')
    : normalizeString(commerce.network) ?? 'base-mainnet';
  const terms = mode === 'metered'
    ? {
        schema: PRICING_SCHEMA,
        mode,
        basis: 'total_tokens',
        rateMinorUnitsPer1K: positiveInteger(commerce.rateMinorUnitsPer1K, null, 'rateMinorUnitsPer1K'),
        asset,
        assetDecimals,
        network,
        payTo: requireCommerceString(commerce.payTo, 'payTo'),
        minChargeMinorUnits: nonNegativeInteger(commerce.minChargeMinorUnits ?? 1, 'minChargeMinorUnits')
      }
    : {
        schema: PRICING_SCHEMA,
        mode,
        basis: 'total_tokens',
        rateMinorUnitsPer1K: 0,
        asset,
        assetDecimals,
        network,
        payTo: null,
        minChargeMinorUnits: 0
      };
  return {
    ...terms,
    revision: `pricing-${commitmentFor(terms).slice(7, 23)}`
  };
}

function pricingForExpert(expert) {
  return expert.pricing ?? normalizeCommerce({ mode: 'free' });
}

function quoteTokenEstimate(state, pricing, renderedPrompt, pack) {
  if (pricing.mode === 'free') {
    return {
      promptTokens: estimateTokens(renderedPrompt),
      tokenizerID: 'heuristic-characters-per-four',
      authoritative: false
    };
  }
  const estimator = state.tokenEstimator;
  if (typeof estimator !== 'function') {
    throw marketplaceError(
      'TOKEN_ESTIMATOR_UNAVAILABLE',
      'metered inference requires a configured authoritative token estimator',
      503,
      true
    );
  }
  const estimate = estimator({ text: renderedPrompt, modelID: pack.afm.model_id });
  if (estimate && typeof estimate.then === 'function') {
    throw marketplaceError('TOKEN_ESTIMATOR_INVALID', 'tokenEstimator must return synchronously', 503);
  }
  const promptTokens = Number(estimate?.promptTokens ?? estimate?.prompt_tokens ?? estimate);
  const tokenizerID = normalizeTokenizerID(estimate?.tokenizerID ?? estimate?.tokenizer_id);
  if (!Number.isSafeInteger(promptTokens) || promptTokens <= 0 || !tokenizerID) {
    throw marketplaceError('TOKEN_ESTIMATOR_INVALID', 'tokenEstimator returned invalid prompt usage metadata', 503);
  }
  return { promptTokens, tokenizerID, authoritative: true };
}

function publishedRunner(state, runnerID) {
  const normalizedRunnerID = requireString(runnerID, 'runnerID');
  const pack = state.packs.get(normalizedRunnerID);
  const expert = state.experts.get(normalizedRunnerID);
  if (!pack || !expert) {
    throw marketplaceError('RUNNER_NOT_FOUND', 'published runner not found', 404);
  }
  if (pack.status !== 'marketplace') {
    throw marketplaceError('RUNNER_NOT_PUBLISHED', 'runner is not published to the marketplace', 409);
  }
  return { pack, expert };
}

function normalizeInferenceRequest(payload, pack) {
  const prompt = requireString(payload?.prompt, 'prompt');
  if (payload?.context != null && typeof payload.context !== 'string') {
    throw marketplaceError('INVALID_CONTEXT', 'context must be a string', 422);
  }
  const context = payload?.context ?? '';
  const parameters = payload?.parameters ?? {};
  const configuredMax = positiveInteger(pack.prompting.params.max_tokens, 900, 'pack max_tokens');
  const maxTokens = positiveInteger(
    parameters.maxTokens ?? parameters.max_tokens ?? payload?.maxTokens ?? configuredMax,
    configuredMax,
    'maxTokens'
  );
  if (maxTokens > configuredMax) {
    throw marketplaceError('OUTPUT_TOKEN_CAP_EXCEEDED', `maxTokens cannot exceed the runner cap of ${configuredMax}`, 422);
  }
  const rawTemperature = parameters.temperature ?? pack.prompting.params.temperature;
  const temperature = Number(rawTemperature);
  if (!Number.isFinite(temperature) || temperature < 0 || temperature > 2) {
    throw marketplaceError('INVALID_TEMPERATURE', 'temperature must be between 0 and 2', 422);
  }
  const normalized = { prompt, context, parameters: { maxTokens, temperature } };
  if (estimateTokens(renderRunnerPrompt(pack, normalized)) + maxTokens > pack.policy.max_context) {
    throw marketplaceError('CONTEXT_TOKEN_CAP_EXCEEDED', 'prompt, context, and output cap exceed the runner context policy', 422);
  }
  return normalized;
}

function renderRunnerPrompt(pack, request) {
  return pack.prompting.template
    .replaceAll('{{system}}', pack.prompting.system)
    .replaceAll('{{context}}', request.context)
    .replaceAll('{{prompt}}', request.prompt);
}

function validateQuoteForExecution(state, quote, expert, request, inputCommitment) {
  if (quote.status !== 'open') {
    throw marketplaceError('QUOTE_NOT_OPEN', `inference quote is ${quote.status}`, 409);
  }
  ensureQuoteNotExpired(state, quote);
  if (quote.profileCommitment !== expertProfileCommitment(expert) || quote.pricing.revision !== pricingForExpert(expert).revision) {
    quote.status = 'stale';
    throw marketplaceError('QUOTE_STALE', 'expert profile or pricing changed after the quote was created', 409);
  }
  const pack = state.packs.get(quote.runnerID);
  const manifestCommitment = pack?.hashes?.manifest ?? (pack ? commitmentFor(pack) : null);
  if (!manifestCommitment || manifestCommitment !== quote.manifestCommitment) {
    quote.status = 'stale';
    throw marketplaceError('QUOTE_STALE', 'runner manifest changed after the quote was created', 409);
  }
  if (commitmentFor(normalizeRoyaltyTerms(pack.royalties)) !== commitmentFor(quote.royaltyTerms)) {
    quote.status = 'stale';
    throw marketplaceError('QUOTE_STALE', 'runner royalty terms changed after the quote was created', 409);
  }
  if (inputCommitment !== quote.inputCommitment) {
    throw marketplaceError('QUOTE_INPUT_MISMATCH', 'prompt or context does not match the inference quote', 409);
  }
  if (commitmentFor(request.parameters) !== quote.parametersCommitment) {
    throw marketplaceError('QUOTE_PARAMETERS_MISMATCH', 'inference parameters do not match the quote', 409);
  }
}

function ensureQuoteNotExpired(state, quote) {
  if (Date.parse(quote.expiresAt) <= state.now().getTime()) {
    quote.status = 'expired';
    throw marketplaceError('QUOTE_EXPIRED', 'inference quote has expired', 409);
  }
}

function inferenceExecutorFor(state) {
  if (typeof state.inferenceExecutor === 'function') {
    return state.inferenceExecutor;
  }
  if (state.inferenceExecutor && typeof state.inferenceExecutor.execute === 'function') {
    return request => state.inferenceExecutor.execute(request);
  }
  throw marketplaceError('EXECUTOR_UNAVAILABLE', 'no inference executor is configured', 503, true);
}

function paymentProcessorFor(state) {
  const processor = state.paymentProcessor;
  if (!processor || typeof processor.authorize !== 'function' || typeof processor.settle !== 'function') {
    throw marketplaceError('PAYMENT_PROCESSOR_UNAVAILABLE', 'no payment processor is configured for metered inference', 503, true);
  }
  return processor;
}

async function authorizePayment(state, quote, payment, inference) {
  const processor = paymentProcessorFor(state);
  let result;
  try {
    result = await processor.authorize({
      quote: paymentSafeQuote(quote),
      payment,
      inferenceID: inference.id
    });
  } catch {
    throw marketplaceError('PAYMENT_AUTHORIZATION_FAILED', 'payment authorization failed', 402);
  }
  const authorizationID = normalizeOpaqueReference(
    result?.authorizationID ?? result?.authorization_id,
    'authorizationID'
  );
  const authorizedAmountMinorUnits = Number(result?.authorizedAmountMinorUnits ?? result?.authorized_amount_minor_units);
  if (
    result?.authorized !== true
    || !authorizationID
    || !Number.isSafeInteger(authorizedAmountMinorUnits)
    || authorizedAmountMinorUnits !== quote.maxAmountMinorUnits
  ) {
    throw marketplaceError('PAYMENT_AUTHORIZATION_INVALID', 'payment authorization amount must exactly match the quoted maximum', 402);
  }
  if (
    result?.requirementHash !== quote.requirementHash
    || result?.quoteID !== quote.id
    || result?.inferenceID !== inference.id
    || result?.expiresAt !== quote.expiresAt
  ) {
    throw marketplaceError('PAYMENT_AUTHORIZATION_INVALID', 'payment authorization is not bound to the quote requirement', 402);
  }
  for (const [field, expected] of [
    ['asset', quote.pricing.asset],
    ['network', quote.pricing.network],
    ['payTo', quote.pricing.payTo]
  ]) {
    if (result?.[field] !== expected) {
      throw marketplaceError('PAYMENT_AUTHORIZATION_INVALID', `payment authorization ${field} does not match the quote`, 402);
    }
  }
  return {
    authorizationID,
    authorizedAmountMinorUnits,
    paymentReference: normalizeOpaqueReference(
      result?.paymentReference ?? result?.payment_reference,
      'paymentReference'
    )
  };
}

async function settlePayment(state, quote, authorization, chargedAmountMinorUnits, inference, evidence) {
  const processor = paymentProcessorFor(state);
  const usageCommitment = commitmentFor(evidence.usage);
  const royaltySplitCommitment = commitmentFor(evidence.royaltySplit);
  let result;
  try {
    result = await processor.settle({
      quote: paymentSafeQuote(quote),
      authorization: { ...authorization },
      chargedAmountMinorUnits,
      inferenceID: inference.id,
      usage: evidence.usage,
      usageCommitment,
      outputCommitment: evidence.outputCommitment,
      royaltySplit: evidence.royaltySplit,
      royaltySplitCommitment
    });
  } catch {
    throw marketplaceError('PAYMENT_SETTLEMENT_FAILED', 'payment settlement failed', 502, true);
  }
  const settledAmount = Number(result?.chargedAmountMinorUnits ?? result?.charged_amount_minor_units);
  const authorizationRemainderMinorUnits = Number(
    result?.authorizationRemainderMinorUnits ?? result?.authorization_remainder_minor_units
  );
  const expectedRemainder = authorization.authorizedAmountMinorUnits - chargedAmountMinorUnits;
  const settlementID = normalizeOpaqueReference(result?.settlementID ?? result?.settlement_id, 'settlementID');
  if (
    result?.settled !== true
    || !settlementID
    || !Number.isSafeInteger(settledAmount)
    || settledAmount < 0
    || settledAmount !== chargedAmountMinorUnits
    || !Number.isSafeInteger(authorizationRemainderMinorUnits)
    || authorizationRemainderMinorUnits !== expectedRemainder
    || result?.authorizationID !== authorization.authorizationID
    || result?.requirementHash !== quote.requirementHash
    || result?.quoteID !== quote.id
    || result?.inferenceID !== inference.id
    || result?.usageCommitment !== usageCommitment
    || result?.outputCommitment !== evidence.outputCommitment
    || result?.royaltySplitCommitment !== royaltySplitCommitment
  ) {
    throw marketplaceError('PAYMENT_SETTLEMENT_INVALID', 'payment settlement does not match authoritative usage', 502);
  }
  return {
    status: 'settled',
    settlementID,
    transactionReference: normalizeOpaqueReference(
      result?.transactionReference ?? result?.transaction_reference,
      'transactionReference'
    ),
    authorizationRemainderMinorUnits,
    usageCommitment,
    royaltySplitCommitment
  };
}

async function releasePayment(state, authorization, inference, error) {
  const processor = state.paymentProcessor;
  if (!processor || typeof processor.release !== 'function') {
    return { confirmed: false, releaseReference: null };
  }
  try {
    const result = await processor.release({
      authorization: { ...authorization },
      inferenceID: inference.id,
      reason: normalizeMarketplaceError(error).code
    });
    return {
      confirmed: result?.released === true
        && result?.authorizationID === authorization.authorizationID
        && result?.inferenceID === inference.id,
      releaseReference: normalizeOpaqueReference(
        result?.releaseReference ?? result?.release_reference,
        'releaseReference'
      )
    };
  } catch {
    // The failed inference remains failed even if an external release needs reconciliation.
    return { confirmed: false, releaseReference: null };
  }
}

async function executeWithProvider(executor, request) {
  try {
    return await executor(request);
  } catch {
    throw marketplaceError('EXECUTOR_FAILED', 'inference executor failed', 502, true);
  }
}

function normalizeAuthoritativeUsage(usage) {
  if (!usage || typeof usage !== 'object') {
    throw marketplaceError('AUTHORITATIVE_USAGE_REQUIRED', 'executor did not return authoritative token usage', 502);
  }
  const promptTokens = Number(usage.promptTokens ?? usage.prompt_tokens);
  const completionTokens = Number(usage.completionTokens ?? usage.completion_tokens);
  const totalTokens = Number(usage.totalTokens ?? usage.total_tokens);
  const tokenizerID = normalizeTokenizerID(usage.tokenizerID ?? usage.tokenizer_id);
  const usageAttestation = normalizeOpaqueReference(
    usage.usageAttestation ?? usage.usage_attestation,
    'usageAttestation',
    4_096
  );
  if (
    ![promptTokens, completionTokens, totalTokens].every(value => Number.isSafeInteger(value) && value >= 0)
    || totalTokens !== promptTokens + completionTokens
    || totalTokens === 0
    || !tokenizerID
    || !usageAttestation
  ) {
    throw marketplaceError('AUTHORITATIVE_USAGE_INVALID', 'executor usage must include consistent token counts, tokenizer ID, and usage attestation', 502);
  }
  return { promptTokens, completionTokens, totalTokens, tokenizerID, usageAttestation };
}

function privacySafeUsage(usage) {
  return {
    promptTokens: usage.promptTokens,
    completionTokens: usage.completionTokens,
    totalTokens: usage.totalTokens,
    tokenizerID: usage.tokenizerID,
    usageAttestationCommitment: commitmentFor({ attestation: usage.usageAttestation })
  };
}

function normalizeRoyaltyTerms(royalties = {}) {
  const creatorBPS = nonNegativeInteger(royalties.creator_bps ?? royalties.creatorBPS ?? 0, 'creator_bps');
  const dataBPS = nonNegativeInteger(royalties.data_bps ?? royalties.dataBPS ?? 0, 'data_bps');
  if (creatorBPS + dataBPS > 10_000) {
    throw marketplaceError('INVALID_ROYALTIES', 'creator and data royalties cannot exceed 10,000 bps', 422);
  }
  return { creatorBPS, dataBPS };
}

function allocateRoyalties(amountMinorUnits, royalties = {}) {
  const { creatorBPS, dataBPS } = normalizeRoyaltyTerms(royalties);
  const amount = BigInt(nonNegativeInteger(amountMinorUnits, 'amountMinorUnits'));
  const creatorAmountMinorUnits = Number((amount * BigInt(creatorBPS)) / 10_000n);
  const dataAmountMinorUnits = Number((amount * BigInt(dataBPS)) / 10_000n);
  return {
    creatorBPS,
    dataBPS,
    creatorAmountMinorUnits,
    dataAmountMinorUnits,
    providerAmountMinorUnits: Number(amount) - creatorAmountMinorUnits - dataAmountMinorUnits
  };
}

function receiptPricing(pricing) {
  return {
    schema: pricing.schema,
    mode: pricing.mode,
    basis: pricing.basis,
    revision: pricing.revision,
    rateMinorUnitsPer1K: pricing.rateMinorUnitsPer1K,
    minChargeMinorUnits: pricing.minChargeMinorUnits,
    asset: pricing.asset,
    assetDecimals: pricing.assetDecimals,
    network: pricing.network,
    payTo: pricing.payTo
  };
}

function paymentSafeQuote(quote) {
  return {
    id: quote.id,
    runnerID: quote.runnerID,
    expertID: quote.expertID,
    modelID: quote.modelID,
    profileCommitment: quote.profileCommitment,
    manifestCommitment: quote.manifestCommitment,
    inputCommitment: quote.inputCommitment,
    parametersCommitment: quote.parametersCommitment,
    promptTokens: quote.promptTokensEstimated,
    tokenizerID: quote.quoteTokenizerID,
    maxBillableTokens: quote.maxBillableTokens,
    maxAmountMinorUnits: quote.maxAmountMinorUnits,
    pricing: receiptPricing(quote.pricing),
    royaltyTerms: quote.royaltyTerms,
    requirementHash: quote.requirementHash,
    expiresAt: quote.expiresAt
  };
}

function expertProfileCommitment(expert) {
  return commitmentFor({
    id: expert.id,
    profileSig: expert.profileSig,
    baseModel: expert.baseModel,
    pricing: pricingForExpert(expert),
    payoutAddr: expert.payoutAddr,
    ingestUrl: expert.ingestUrl
  });
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

function estimateTokens(text) {
  return Math.max(1, Math.ceil(text.length / 4));
}

function decimalMinorUnits(amountMinorUnits, decimals) {
  const amount = BigInt(nonNegativeInteger(amountMinorUnits, 'amountMinorUnits')).toString();
  const precision = nonNegativeInteger(decimals, 'assetDecimals');
  if (precision === 0) {
    return amount;
  }
  const padded = amount.padStart(precision + 1, '0');
  const whole = padded.slice(0, -precision);
  const fraction = padded.slice(-precision).replace(/0+$/, '');
  return fraction ? `${whole}.${fraction}` : whole;
}

function commitmentFor(value) {
  const digest = createHash('sha256').update(canonicalJSON(value)).digest('hex');
  return `sha256:${digest}`;
}

function canonicalJSON(value) {
  return JSON.stringify(canonicalValue(value));
}

function canonicalValue(value) {
  if (Array.isArray(value)) {
    return value.map(canonicalValue);
  }
  if (value && typeof value === 'object') {
    return Object.keys(value).sort().reduce((result, key) => {
      if (value[key] !== undefined) {
        result[key] = canonicalValue(value[key]);
      }
      return result;
    }, {});
  }
  return value;
}

function requireIdempotencyKey(value) {
  const key = normalizeString(Array.isArray(value) ? value[0] : value);
  if (!key) {
    throw marketplaceError('IDEMPOTENCY_KEY_REQUIRED', 'Idempotency-Key is required for inference execution', 400);
  }
  if (key.length > 200 || /[\r\n]/.test(key)) {
    throw marketplaceError('INVALID_IDEMPOTENCY_KEY', 'Idempotency-Key must be at most 200 characters without newlines', 400);
  }
  return key;
}

function positiveInteger(value, fallback, fieldName) {
  if (value == null) {
    if (fallback != null) {
      return fallback;
    }
    throw marketplaceError('INVALID_NUMBER', `${fieldName} must be a positive integer`, 422);
  }
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number <= 0) {
    throw marketplaceError('INVALID_NUMBER', `${fieldName} must be a positive integer`, 422);
  }
  return number;
}

function nonNegativeInteger(value, fieldName) {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < 0) {
    throw marketplaceError('INVALID_NUMBER', `${fieldName} must be a non-negative integer`, 422);
  }
  return number;
}

function requireCommerceString(value, fieldName) {
  const normalized = normalizeString(value);
  if (!normalized) {
    throw marketplaceError('INVALID_PRICING', `${fieldName} is required for metered pricing`, 422);
  }
  return normalized;
}

function normalizeTokenizerID(value) {
  const normalized = normalizeString(value);
  return normalized && /^[A-Za-z0-9._:/@-]{1,128}$/.test(normalized) ? normalized : null;
}

function normalizeOpaqueReference(value, fieldName, maxLength = 512) {
  if (value == null) {
    return null;
  }
  const normalized = normalizeString(value);
  if (!normalized || normalized.length > maxLength || /[\u0000-\u001f\u007f]/.test(normalized)) {
    throw marketplaceError('PROVIDER_METADATA_INVALID', `${fieldName} contains invalid opaque metadata`, 502);
  }
  return normalized;
}

function optionalCommitment(value) {
  if (value == null) {
    return null;
  }
  return commitmentFor({ value: String(value) });
}

function normalizePublicBaseURL(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw marketplaceError('INVALID_PUBLIC_URL', 'publicBaseURL must be an absolute HTTP URL', 422);
  }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) {
    throw marketplaceError('INVALID_PUBLIC_URL', 'publicBaseURL must be an HTTP URL without credentials', 422);
  }
  return url.toString().replace(/\/$/, '');
}

function marketplaceError(code, message, statusCode = 400, retryable = false, details = null) {
  const error = new Error(message);
  error.code = code;
  error.statusCode = statusCode;
  error.retryable = retryable;
  error.details = details;
  return error;
}

function normalizeMarketplaceError(error) {
  if (error?.code && Number.isInteger(error?.statusCode)) {
    return {
      code: error.code,
      message: error.message,
      statusCode: error.statusCode,
      retryable: Boolean(error.retryable),
      details: error.details ?? null
    };
  }
  return {
    code: 'MARKETPLACE_REQUEST_INVALID',
    message: String(error?.message ?? error),
    statusCode: Number.isInteger(error?.statusCode) ? error.statusCode : 400,
    retryable: false,
    details: null
  };
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
