import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import {
  createMarketplaceState,
  createTrainingJob,
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
