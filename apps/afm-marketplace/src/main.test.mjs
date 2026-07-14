import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import {
  calculateCharge,
  createInferenceQuote,
  createMarketplaceState,
  createTrainingJob,
  executeInference,
  getProviderSummary,
  publishTrainingJob,
  selfTest,
  startMarketplaceServer
} from './main.mjs';

const fixedNow = () => new Date('2026-01-01T00:00:00.000Z');

function publishableRequest(overrides = {}) {
  return {
    displayName: 'Local Legal Expert',
    objective: 'Answer approved legal policy questions.',
    datasetSummary: 'Redacted approved examples.',
    sampleCount: 12,
    policy: {
      baseModelID: 'apple.foundation-model.local',
      method: 'loraAdapter',
      privacyMode: 'redactedA2A',
      allowA2A: true,
      publishToAFMarket: true,
      maxTrainingExamples: 250,
      domainTags: ['law', 'policy', 'law'],
      ...(overrides.policy ?? {})
    },
    ...overrides
  };
}

function meteredCommerce(overrides = {}) {
  return {
    mode: 'metered',
    rateMinorUnitsPer1K: 25,
    asset: 'USDC',
    assetDecimals: 6,
    network: 'base-sepolia',
    payTo: '0xseller',
    minChargeMinorUnits: 1,
    ...overrides
  };
}

function publishRunner(state, commerce) {
  const request = publishableRequest(commerce === undefined ? {} : { commerce });
  return publishTrainingJob(state, createTrainingJob(state, request).id);
}

function callableExecutor(implementation) {
  const calls = [];
  const execute = async request => {
    calls.push(request);
    return implementation(request);
  };
  const executor = request => execute(request);
  executor.execute = execute;
  executor.calls = calls;
  return executor;
}

function successfulExecutor(overrides = {}) {
  return callableExecutor(async () => ({
    text: 'Seller-side inference result',
    usage: {
      promptTokens: 19,
      completionTokens: 12,
      totalTokens: 31,
      tokenizerID: 'test-tokenizer-v1',
      usageAttestation: 'usage-attestation-test'
    },
    runtimeRequestID: 'runtime-request-test',
    ...overrides
  }));
}

function callablePaymentProcessor() {
  const authorizations = [];
  const settlements = [];
  const processor = async request => processor.authorize(request);
  processor.authorize = async request => {
    authorizations.push(request);
    return {
      authorized: true,
      authorizationID: 'authorization-test',
      authorizedAmountMinorUnits: request.quote.maxAmountMinorUnits,
      requirementHash: request.quote.requirementHash,
      quoteID: request.quote.id,
      inferenceID: request.inferenceID,
      expiresAt: request.quote.expiresAt,
      asset: request.quote.pricing.asset,
      network: request.quote.pricing.network,
      payTo: request.quote.pricing.payTo,
      paymentReference: 'payment-test'
    };
  };
  processor.settle = async request => {
    settlements.push(request);
    return {
      settled: true,
      settlementID: 'settlement-test',
      chargedAmountMinorUnits: request.chargedAmountMinorUnits,
      authorizationID: request.authorization.authorizationID,
      requirementHash: request.quote.requirementHash,
      quoteID: request.quote.id,
      inferenceID: request.inferenceID,
      usageCommitment: request.usageCommitment,
      outputCommitment: request.outputCommitment,
      royaltySplitCommitment: request.royaltySplitCommitment,
      authorizationRemainderMinorUnits:
        request.authorization.authorizedAmountMinorUnits - request.chargedAmountMinorUnits,
      transactionReference: 'transaction-test'
    };
  };
  processor.authorizations = authorizations;
  processor.settlements = settlements;
  return processor;
}

function quoteRecord(value) {
  return value.quote ?? value;
}

function inferenceRecord(value) {
  return value.inference ?? value;
}

function inferenceText(value) {
  return value.text ?? value.output?.text ?? value.inference?.text ?? value.inference?.output?.text;
}

describe('local AFM marketplace catalog', () => {
  it('creates deterministic local adapter artifacts from training requests', () => {
    const state = createMarketplaceState({ now: fixedNow });
    const first = createTrainingJob(state, publishableRequest());
    const second = createTrainingJob(state, publishableRequest());

    assert.equal(first.id, second.id);
    assert.equal(first.publishStatus, 'draft');
    assert.equal(first.status, 'readyForLocalUse');
    assert.equal(first.publishReadiness, 'needsAttestation');
    assert.equal(first.request.policy.domainTags.join(','), 'law,policy');
    assert.equal(first.runnerPack.runner_id, first.outputRunnerID);
    assert.equal(first.runnerPack.afm.model_id, 'apple.foundation-model.local');
    assert.equal(first.runnerPack.policy.allowed_domains.join(','), 'law,policy');
    assert.equal(first.peerExpert.id, first.outputRunnerID);
    assert.match(first.adapterStatus, /LoRA adapter/);
  });

  it('publishes trained experts into pack and expert marketplace indexes', () => {
    const state = createMarketplaceState({ now: fixedNow });
    const job = createTrainingJob(state, publishableRequest());
    const published = publishTrainingJob(state, job.id);

    assert.equal(published.status, 'publishReady');
    assert.equal(published.publishStatus, 'published');
    assert.equal(published.publishReadiness, 'readyForAFMarket');
    assert.equal(state.packs.get(published.outputRunnerID).runner_id, published.outputRunnerID);
    assert.equal(state.experts.get(published.outputRunnerID).name, 'Local Legal Expert');
  });

  it('blocks marketplace publish when policy keeps the expert local only', () => {
    const state = createMarketplaceState({ now: fixedNow });
    const job = createTrainingJob(
      state,
      publishableRequest({
        policy: {
          privacyMode: 'localOnly',
          allowA2A: false
        }
      })
    );

    assert.equal(job.publishStatus, 'blocked');
    assert.throws(() => publishTrainingJob(state, job.id), /not publishable/);
  });

  it('passes package self-test', async () => {
    const result = await selfTest();
    assert.equal(result.status, 'ready');
    assert.equal(result.packs, 1);
    assert.equal(result.experts, 1);
    assert.equal(result.trainingJobs, 1);
  });
});

describe('seller-side inference commerce', () => {
  it('defaults training requests to explicit free commerce and publishes derived provider fields', () => {
    const state = createMarketplaceState({
      now: fixedNow,
      publicBaseURL: 'https://seller.example.test'
    });
    const published = publishRunner(state);

    assert.equal(published.request.commerce.mode, 'free');
    assert.equal(published.peerExpert.pricePer1k, 0);
    assert.equal(published.peerExpert.payoutAddr, null);
    assert.equal(published.peerExpert.pricing.mode, 'free');
    assert.equal(published.peerExpert.pricing.rateMinorUnitsPer1K, 0);
    assert.match(published.peerExpert.ingestUrl, /^https:\/\/seller\.example\.test\//);
    assert.match(published.peerExpert.ingestUrl, new RegExp(encodeURIComponent(published.outputRunnerID)));
  });

  it('calculates integer minor-unit charges with ceiling and minimum-charge rules', () => {
    const noMinimum = meteredCommerce({ rateMinorUnitsPer1K: 25, minChargeMinorUnits: 0 });
    assert.equal(calculateCharge(noMinimum, 0), 0);
    assert.equal(calculateCharge(noMinimum, 1), 1);
    assert.equal(calculateCharge(noMinimum, 999), 25);
    assert.equal(calculateCharge(noMinimum, 1_000), 25);
    assert.equal(calculateCharge(noMinimum, 1_001), 26);
    assert.equal(calculateCharge(meteredCommerce({ rateMinorUnitsPer1K: 1, minChargeMinorUnits: 7 }), 1), 7);
    assert.equal(calculateCharge({ mode: 'free' }, 50_000), 0);
  });

  it('requires complete metered pricing and an authoritative quote tokenizer', () => {
    const state = createMarketplaceState({ now: fixedNow, inferenceExecutor: successfulExecutor() });
    assert.throws(
      () => createTrainingJob(state, publishableRequest({ commerce: meteredCommerce({ network: undefined }) })),
      error => error.code === 'INVALID_PRICING'
    );

    const published = publishRunner(state, meteredCommerce());
    assert.throws(
      () => createInferenceQuote(state, published.outputRunnerID, { prompt: 'requires tokenizer' }),
      error => error.code === 'TOKEN_ESTIMATOR_UNAVAILABLE' && error.statusCode === 503
    );

    state.tokenEstimator = () => ({
      promptTokens: published.runnerPack.policy.max_context,
      tokenizerID: 'metered-tokenizer-v1'
    });
    assert.throws(
      () => createInferenceQuote(state, published.outputRunnerID, { prompt: 'exceeds model context' }),
      error => error.code === 'CONTEXT_TOKEN_CAP_EXCEEDED' && error.statusCode === 422
    );
  });

  it('quotes and executes explicit-free inference without exposing prompt material', async () => {
    const executor = successfulExecutor();
    const state = createMarketplaceState({ now: fixedNow, inferenceExecutor: executor });
    const published = publishRunner(state);
    const prompt = 'private prompt for the legal expert';
    const context = 'private approved context passage';
    const request = {
      prompt,
      context,
      parameters: { maxTokens: 128, temperature: 0.1 }
    };

    const quote = quoteRecord(createInferenceQuote(state, published.outputRunnerID, request));
    assert.equal(quote.runnerID, published.outputRunnerID);
    assert.equal(quote.requirementHash.length > 0, true);
    assert.equal(quote.maxAmountMinorUnits, 0);
    assert.equal(quote.pricing.mode, 'free');
    assert.doesNotMatch(JSON.stringify(quote), new RegExp(prompt));
    assert.doesNotMatch(JSON.stringify(quote), new RegExp(context));

    const result = await executeInference(
      state,
      published.outputRunnerID,
      { quoteID: quote.id, ...request },
      'free-inference-key'
    );
    const inference = inferenceRecord(result);
    const receipt = state.receipts.get(inference.receiptID);
    assert.equal(inferenceText(result), 'Seller-side inference result');
    assert.equal(inference.status, 'completed');
    assert.equal(receipt.chargedAmountMinorUnits, 0);
    assert.equal(receipt.usage.totalTokens, 31);
    assert.equal(receipt.usage.tokenizerID, 'test-tokenizer-v1');
    assert.match(receipt.runtime.requestCommitment, /^sha256:/);
    assert.equal(receipt.runtime.usageAttestation, undefined);
    assert.match(receipt.runtime.usageAttestationCommitment, /^sha256:/);
    assert.equal(executor.calls.length, 1);
    assert.doesNotMatch(JSON.stringify(result), new RegExp(prompt));
    assert.doesNotMatch(JSON.stringify(result), new RegExp(context));
  });

  it('authorizes, meters, and settles a metered inference using authoritative runtime usage', async () => {
    const executor = successfulExecutor({
      usage: {
        promptTokens: 500,
        completionTokens: 399,
        totalTokens: 899,
        tokenizerID: 'metered-tokenizer-v1',
        usageAttestation: 'metered-usage-attestation'
      }
    });
    const paymentProcessor = callablePaymentProcessor();
    const state = createMarketplaceState({
      now: fixedNow,
      inferenceExecutor: executor,
      tokenEstimator: () => ({ promptTokens: 500, tokenizerID: 'metered-tokenizer-v1' }),
      paymentProcessor
    });
    const published = publishRunner(state, meteredCommerce());
    const request = {
      prompt: 'metered prompt',
      context: 'metered context',
      parameters: { maxTokens: 900, temperature: 0.2 }
    };
    const quote = quoteRecord(createInferenceQuote(state, published.outputRunnerID, request));

    assert.equal(quote.pricing.mode, 'metered');
    assert.equal(quote.pricing.asset, 'USDC');
    assert.equal(quote.pricing.payTo, '0xseller');
    assert.equal(quote.maxAmountMinorUnits > 0, true);
    assert.equal(quote.requirementHash.length > 0, true);

    const result = await executeInference(
      state,
      published.outputRunnerID,
      {
        quoteID: quote.id,
        ...request,
        payment: {
          requirementHash: quote.requirementHash,
          maxAmountMinorUnits: quote.maxAmountMinorUnits,
          authorization: 'signed-payment-test'
        }
      },
      'metered-inference-key'
    );
    const inference = inferenceRecord(result);
    const receipt = state.receipts.get(inference.receiptID);

    assert.equal(inferenceText(result), 'Seller-side inference result');
    assert.equal(receipt.usage.totalTokens, 899);
    assert.equal(receipt.chargedAmountMinorUnits, 23);
    assert.equal(receipt.status, 'settled');
    assert.equal(receipt.payment.settlementID, 'settlement-test');
    assert.match(receipt.payment.usageCommitment, /^sha256:/);
    assert.match(receipt.payment.royaltySplitCommitment, /^sha256:/);
    assert.equal(paymentProcessor.authorizations.length, 1);
    assert.equal(paymentProcessor.settlements.length, 1);
    assert.equal(executor.calls.length, 1);
  });

  it('fails closed before execution when metered payment is missing or bound to the wrong requirement', async () => {
    const executor = successfulExecutor();
    const paymentProcessor = callablePaymentProcessor();
    const state = createMarketplaceState({
      now: fixedNow,
      inferenceExecutor: executor,
      tokenEstimator: () => ({ promptTokens: 19, tokenizerID: 'test-tokenizer-v1' }),
      paymentProcessor
    });
    const published = publishRunner(state, meteredCommerce());
    const request = { prompt: 'paid prompt', parameters: { maxTokens: 64 } };
    const quote = quoteRecord(createInferenceQuote(state, published.outputRunnerID, request));

    await assert.rejects(
      executeInference(
        state,
        published.outputRunnerID,
        { quoteID: quote.id, ...request },
        'missing-payment-key'
      ),
      error => /payment/i.test(error.message) && error.statusCode === 402
    );
    await assert.rejects(
      executeInference(
        state,
        published.outputRunnerID,
        {
          quoteID: quote.id,
          ...request,
          payment: { requirementHash: 'wrong-requirement-hash' }
        },
        'wrong-payment-key'
      ),
      error => /requirement|payment/i.test(error.message) && error.statusCode === 402
    );

    assert.equal(executor.calls.length, 0);
    assert.equal(paymentProcessor.authorizations.length, 0);
    assert.equal(paymentProcessor.settlements.length, 0);
  });

  it('replays identical idempotent execution and rejects payload conflicts without running twice', async () => {
    const executor = successfulExecutor();
    const state = createMarketplaceState({ now: fixedNow, inferenceExecutor: executor });
    const published = publishRunner(state);
    const request = { prompt: 'idempotent prompt', parameters: { maxTokens: 32 } };
    const quote = quoteRecord(createInferenceQuote(state, published.outputRunnerID, request));
    const execution = { quoteID: quote.id, ...request };

    const first = await executeInference(state, published.outputRunnerID, execution, 'stable-key');
    const replay = await executeInference(state, published.outputRunnerID, execution, 'stable-key');
    assert.deepEqual(replay, first);
    assert.equal(executor.calls.length, 1);

    await assert.rejects(
      executeInference(
        state,
        published.outputRunnerID,
        { ...execution, prompt: 'changed prompt' },
        'stable-key'
      ),
      error => /idempot|conflict/i.test(error.message) && error.statusCode === 409
    );
    assert.equal(executor.calls.length, 1);
  });

  it('rejects expired quotes and quotes invalidated by expert profile mutation', async () => {
    let now = new Date('2026-01-01T00:00:00.000Z');
    const executor = successfulExecutor();
    const state = createMarketplaceState({
      now: () => now,
      quoteTTLMS: 1_000,
      inferenceExecutor: executor
    });
    const published = publishRunner(state);
    const expiredRequest = { prompt: 'expires before execution' };
    const expiredQuote = quoteRecord(createInferenceQuote(state, published.outputRunnerID, expiredRequest));
    now = new Date('2026-01-01T00:00:01.001Z');

    await assert.rejects(
      executeInference(
        state,
        published.outputRunnerID,
        { quoteID: expiredQuote.id, ...expiredRequest },
        'expired-quote-key'
      ),
      error => error.code === 'QUOTE_EXPIRED' && error.statusCode === 409
    );

    now = new Date('2026-01-01T00:00:02.000Z');
    const staleRequest = { prompt: 'profile changes before execution' };
    const staleQuote = quoteRecord(createInferenceQuote(state, published.outputRunnerID, staleRequest));
    state.experts.get(published.outputRunnerID).profileSig = 'mutated-profile-signature';
    await assert.rejects(
      executeInference(
        state,
        published.outputRunnerID,
        { quoteID: staleQuote.id, ...staleRequest },
        'stale-profile-key'
      ),
      error => error.code === 'QUOTE_STALE' && error.statusCode === 409
    );
    assert.equal(executor.calls.length, 0);
  });

  it('withholds receipts and marks inference failed when payment settlement is invalid', async () => {
    const executor = successfulExecutor();
    const paymentProcessor = callablePaymentProcessor();
    paymentProcessor.settle = async request => {
      paymentProcessor.settlements.push(request);
      return {
        settled: false,
        settlementID: 'invalid-settlement',
        chargedAmountMinorUnits: request.chargedAmountMinorUnits,
        authorizationID: request.authorization.authorizationID,
        requirementHash: request.quote.requirementHash
      };
    };
    const state = createMarketplaceState({
      now: fixedNow,
      inferenceExecutor: executor,
      tokenEstimator: () => ({ promptTokens: 19, tokenizerID: 'test-tokenizer-v1' }),
      paymentProcessor
    });
    const published = publishRunner(state, meteredCommerce());
    const request = { prompt: 'settlement must succeed', parameters: { maxTokens: 64 } };
    const quote = quoteRecord(createInferenceQuote(state, published.outputRunnerID, request));

    await assert.rejects(
      executeInference(
        state,
        published.outputRunnerID,
        {
          quoteID: quote.id,
          ...request,
          payment: {
            requirementHash: quote.requirementHash,
            maxAmountMinorUnits: quote.maxAmountMinorUnits,
            authorization: 'signed-payment-test'
          }
        },
        'failed-settlement-key'
      ),
      error => error.code === 'PAYMENT_SETTLEMENT_INVALID' && error.statusCode === 502
    );

    assert.equal(executor.calls.length, 1);
    assert.equal(paymentProcessor.authorizations.length, 1);
    assert.equal(paymentProcessor.settlements.length, 1);
    assert.equal(state.receipts.size, 0);
    const failed = Array.from(state.inferences.values()).at(-1);
    assert.equal(failed.status, 'failed');
    assert.equal(failed.reconciliationRequired, true);
  });

  it('rejects executor output without authoritative token usage and publishes a private provider summary', async () => {
    const executor = callableExecutor(async () => ({
      text: 'unmetered output',
      runtimeRequestID: 'missing-usage-runtime-request'
    }));
    const state = createMarketplaceState({ now: fixedNow, inferenceExecutor: executor });
    const published = publishRunner(state);
    const request = { prompt: 'prompt that must not reach summary', context: 'secret summary context' };
    const quote = quoteRecord(createInferenceQuote(state, published.outputRunnerID, request));

    await assert.rejects(
      executeInference(
        state,
        published.outputRunnerID,
        { quoteID: quote.id, ...request },
        'missing-usage-key'
      ),
      error => /usage|token/i.test(error.message) && error.statusCode >= 400
    );

    const summary = getProviderSummary(state);
    const serialized = JSON.stringify(summary);
    assert.equal(summary.publishedRunners, 1);
    assert.equal(summary.meteredExperts, 0);
    assert.equal(summary.inferenceCounts.completed, 0);
    assert.equal(summary.inferenceCounts.failed, 1);
    assert.equal(summary.receipts, 0);
    assert.doesNotMatch(serialized, /prompt that must not reach summary/);
    assert.doesNotMatch(serialized, /secret summary context/);
  });
});

describe('local AFM marketplace HTTP API', () => {
  let server;
  let baseURL;

  before(async () => {
    const started = await startMarketplaceServer({
      hostname: '127.0.0.1',
      port: 0,
      now: fixedNow
    });
    server = started.server;
    baseURL = started.url;
  });

  after(async () => {
    await new Promise(resolve => server.close(resolve));
  });

  it('creates and publishes training jobs over HTTP', async () => {
    const createResponse = await fetch(`${baseURL}/api/training-jobs`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(publishableRequest())
    });
    assert.equal(createResponse.status, 201);
    const created = await createResponse.json();
    assert.equal(created.job.publishStatus, 'draft');

    const publishResponse = await fetch(`${baseURL}/api/training-jobs/${encodeURIComponent(created.job.id)}/publish`, {
      method: 'POST'
    });
    assert.equal(publishResponse.status, 200);
    const published = await publishResponse.json();
    assert.equal(published.pack.runner_id, created.job.outputRunnerID);
    assert.equal(published.expert.id, created.job.outputRunnerID);

    const packsResponse = await fetch(`${baseURL}/api/packs`);
    assert.equal(packsResponse.status, 200);
    const packs = await packsResponse.json();
    assert.equal(packs.packs.length, 1);
    assert.equal(packs.packs[0].runner_id, created.job.outputRunnerID);

    const expertsResponse = await fetch(`${baseURL}/api/experts`);
    assert.equal(expertsResponse.status, 200);
    const experts = await expertsResponse.json();
    assert.equal(experts.experts.length, 1);
    assert.equal(experts.experts[0].id, created.job.outputRunnerID);
  });
});

describe('seller inference HTTP API', () => {
  let server;
  let baseURL;
  let state;
  let published;

  before(async () => {
    const started = await startMarketplaceServer({
      hostname: '127.0.0.1',
      port: 0,
      now: fixedNow,
      inferenceExecutor: successfulExecutor()
    });
    server = started.server;
    baseURL = started.url;
    state = started.state;
    published = publishRunner(state);
  });

  after(async () => {
    await new Promise(resolve => server.close(resolve));
  });

  it('quotes, executes, and retrieves a privacy-preserving free inference receipt', async () => {
    const prompt = 'private HTTP inference prompt';
    const context = 'private HTTP inference context';
    const runnerPath = encodeURIComponent(published.outputRunnerID);
    assert.equal(published.peerExpert.ingestUrl, `${baseURL}/api/runners/${runnerPath}`);

    const quoteResponse = await fetch(`${baseURL}/api/runners/${runnerPath}/quotes`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        prompt,
        context,
        parameters: { maxTokens: 128, temperature: 0.1 }
      })
    });
    assert.equal(quoteResponse.status, 201);
    const { quote } = await quoteResponse.json();
    assert.equal(quote.runnerID, published.outputRunnerID);
    assert.equal(quote.maxAmountMinorUnits, 0);
    assert.doesNotMatch(JSON.stringify(quote), new RegExp(prompt));
    assert.doesNotMatch(JSON.stringify(quote), new RegExp(context));

    const inferenceResponse = await fetch(`${baseURL}/api/runners/${runnerPath}/inferences`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Idempotency-Key': 'http-free-inference-key'
      },
      body: JSON.stringify({
        quoteID: quote.id,
        prompt,
        context,
        parameters: { maxTokens: 128, temperature: 0.1 }
      })
    });
    assert.equal(inferenceResponse.status, 201);
    const completed = await inferenceResponse.json();
    assert.equal(completed.inference.status, 'completed');
    assert.equal(completed.inference.output.text, 'Seller-side inference result');
    assert.equal(completed.receipt.usage.totalTokens, 31);
    assert.equal(completed.receipt.chargedAmountMinorUnits, 0);
    assert.doesNotMatch(JSON.stringify(completed), new RegExp(prompt));
    assert.doesNotMatch(JSON.stringify(completed), new RegExp(context));

    const receiptResponse = await fetch(`${baseURL}/api/receipts/${encodeURIComponent(completed.receipt.id)}`);
    assert.equal(receiptResponse.status, 200);
    const receiptPayload = await receiptResponse.json();
    assert.deepEqual(receiptPayload.receipt, completed.receipt);

    const providerResponse = await fetch(`${baseURL}/api/provider/summary`);
    assert.equal(providerResponse.status, 200);
    const providerPayload = await providerResponse.json();
    assert.equal(providerPayload.provider.publishedRunners, 1);
    assert.equal(providerPayload.provider.inferenceCounts.completed, 1);
    assert.equal(providerPayload.provider.receipts, 1);
  });

  it('returns a stable error envelope when the idempotency key is missing', async () => {
    const runnerPath = encodeURIComponent(published.outputRunnerID);
    const quoteResponse = await fetch(`${baseURL}/api/runners/${runnerPath}/quotes`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: 'missing idempotency test' })
    });
    const { quote } = await quoteResponse.json();

    const response = await fetch(`${baseURL}/api/runners/${runnerPath}/inferences`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ quoteID: quote.id, prompt: 'missing idempotency test' })
    });
    assert.equal(response.status, 400);
    const payload = await response.json();
    assert.equal(payload.error.code, 'IDEMPOTENCY_KEY_REQUIRED');
    assert.equal(payload.error.retryable, false);
  });
});
