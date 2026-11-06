import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
import { webcrypto } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { startFixture } from './server.mjs';

const clientScript = await readFile(new URL('./client.js', import.meta.url), 'utf8');

class Element {
  value = '';
  textContent = '';
  disabled = false;
  dataset = {};
  listeners = new Map();
  addEventListener(name, handler) {
    const handlers = this.listeners.get(name) ?? [];
    handlers.push(handler);
    this.listeners.set(name, handlers);
  }
  dispatch(name) {
    for (const handler of this.listeners.get(name) ?? []) handler({ preventDefault() {} });
  }
}

async function until(predicate) {
  for (let i = 0; i < 200; i += 1) {
    if (predicate()) return;
    await delay(5);
  }
  assert.fail('Client did not reach the expected observable state.');
}

async function fixtureFor(t, options) {
  const fixture = await startFixture({ port: 0, ...options });
  t.after(() => fixture.close());
  return fixture;
}

async function readOracle(fixture) {
  return (await fetch(`${fixture.url}/oracle`, { headers: { Authorization: `Bearer ${fixture.oracleToken}` } })).json();
}

async function mount(fixture, { storage = new Map(), intercept, storageOverride, cryptoOverride } = {}) {
  const { document: current } = await (await fetch(`${fixture.url}/api/documents/alpha/draft-a`)).json();
  const ids = ['draft-form', 'title', 'notes', 'submit-button', 'status', 'revision', 'operation', 'receipt'];
  const elements = new Map(ids.map(id => [id, new Element()]));
  elements.get('draft-form').dataset = {
    fixtureId: fixture.fixtureId, accountId: 'alpha', documentId: 'draft-a',
    revision: String(current.revision), submitted: String(current.submitted)
  };
  elements.get('title').value = current.title;
  elements.get('notes').value = current.notes;
  for (const id of ['title', 'notes', 'submit-button']) elements.get(id).disabled = true;
  const requests = [];
  let idsCreated = 0;
  const transport = async (path, options) => {
    const body = JSON.parse(options.body);
    requests.push(body);
    const send = () => fetch(new URL(path, fixture.url), options);
    return intercept ? intercept({ body, send, index: requests.length - 1 }) : send();
  };
  const context = vm.createContext({
    document: { getElementById: id => elements.get(id) },
    // Deliberately no randomUUID: a physical device can use an HTTP development origin.
    crypto: cryptoOverride ?? { getRandomValues(bytes) { idsCreated += 1; return webcrypto.getRandomValues(bytes); } },
    sessionStorage: storageOverride ?? {
      getItem: key => storage.get(key) ?? null,
      setItem: (key, value) => storage.set(key, value),
      removeItem: key => storage.delete(key)
    },
    fetch: transport, AbortController, setTimeout, clearTimeout
  });
  vm.runInContext(clientScript, context, { filename: 'mobile-browser-fixture/client.js' });
  return {
    elements, storage, requests,
    get idsCreated() { return idsCreated; },
    get state() { return elements.get('status').dataset.state; },
    input(id, value) {
      elements.get(id).value = value;
      elements.get(id).dispatch('input');
    },
    submit() { elements.get('draft-form').dispatch('submit'); }
  };
}

test('actual client serializes autosaves and waits for the latest acknowledged revision before submit', async t => {
  const fixture = await fixtureFor(t);
  let releaseFirst;
  const held = new Promise(resolve => { releaseFirst = resolve; });
  const client = await mount(fixture, {
    intercept: async ({ index, send }) => {
      if (index === 0) await held;
      return send();
    }
  });
  assert.equal(client.state, 'ready');
  for (const id of ['title', 'notes', 'submit-button']) assert.equal(client.elements.get(id).disabled, false);
  client.input('title', 'Cedar workshop');
  await until(() => client.requests.length === 1);
  client.input('notes', 'Room Delta, Tuesday 10:00. Aisle seat and decaf.');
  client.submit();
  assert.equal(client.requests.length, 1);
  assert.equal(client.elements.get('title').disabled, true);
  releaseFirst();
  await until(() => client.state === 'submitted');
  assert.deepEqual(client.requests.map(request => request.kind), ['autosave', 'autosave', 'submit']);
  assert.deepEqual(client.requests.map(request => request.baseRevision), [0, 1, 2]);
  assert.equal(new Set(client.requests.map(request => request.operationId)).size, 3);
  assert.equal(client.requests[2].payload.notes, 'Room Delta, Tuesday 10:00. Aisle seat and decaf.');
  const state = await readOracle(fixture);
  assert.equal(state.documents[0].autosaveCount, 2);
  assert.equal(state.documents[0].submissionCount, 1);
  assert.equal(state.documents[0].revision, 3);
  assert.equal(client.storage.size, 0);
});

test('input alone commits an autosave; the extra change event dispatched by dBrowser does not duplicate it', async t => {
  const fixture = await fixtureFor(t);
  const client = await mount(fixture);
  client.input('notes', 'Typed data is an effect before submit.');
  client.elements.get('notes').dispatch('change');
  await until(() => client.state === 'saved');
  assert.equal(client.requests.length, 1);
  const state = await readOracle(fixture);
  assert.equal(state.documents[0].notes, 'Typed data is an effect before submit.');
  assert.equal(state.documents[0].autosaveCount, 1);
  assert.equal(state.documents[0].submissionCount, 0);
  assert.equal(client.elements.get('submit-button').disabled, false);
});

test('response loss preserves the original UNKNOWN operation across input, submit and reload without replay', async t => {
  const fixture = await fixtureFor(t, { dropResponseAfterCommit: 'autosave' });
  const storage = new Map();
  const client = await mount(fixture, { storage });
  client.input('notes', 'This autosave will commit but lose its response.');
  await until(() => client.state === 'unknown');
  const original = client.requests[0];
  assert.equal(client.idsCreated, 1);
  assert.equal(client.requests.length, 1);
  const pending = JSON.parse([...storage.values()][0]);
  assert.equal(pending.state, 'unknown');
  assert.deepEqual(pending.operation, original);
  client.input('notes', 'Must not create another effect.');
  client.submit();
  await delay(20);
  assert.equal(client.requests.length, 1);
  assert.equal(client.idsCreated, 1);
  assert.equal(client.elements.get('operation').textContent, original.operationId);

  const reloaded = await mount(fixture, { storage });
  assert.equal(reloaded.state, 'unknown');
  reloaded.input('notes', 'Reload must also not retry.');
  reloaded.submit();
  assert.equal(reloaded.idsCreated, 0);
  assert.equal(reloaded.requests.length, 0);
  assert.equal(reloaded.elements.get('operation').textContent, original.operationId);
  const state = await readOracle(fixture);
  assert.equal(state.operations.length, 1);
  assert.equal(state.documents[0].notes, original.payload.notes);
  assert.equal(state.documents[0].submissionCount, 0);
});

test('a lost submit acknowledgement stops with one authoritative submission and no fresh operation', async t => {
  const fixture = await fixtureFor(t, { dropResponseAfterCommit: 'submit' });
  const client = await mount(fixture);
  client.input('notes', 'Final brief.');
  client.submit();
  await until(() => client.state === 'unknown');
  assert.deepEqual(client.requests.map(request => request.kind), ['autosave', 'submit']);
  const submittedOperation = client.requests[1];
  client.submit();
  client.input('title', 'Must stay stopped');
  assert.equal(client.idsCreated, 2);
  assert.equal(client.requests.length, 2);
  assert.equal(JSON.parse([...client.storage.values()][0]).operation.operationId, submittedOperation.operationId);
  const state = await readOracle(fixture);
  assert.equal(state.documents[0].submissionCount, 1);
  assert.equal(state.operations.length, 2);
});

test('an explicit stale-revision refusal stops the client before queued submission', async t => {
  const fixture = await fixtureFor(t);
  const client = await mount(fixture);
  const competing = await fetch(`${fixture.url}/api/operations`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      fixtureId: fixture.fixtureId, operationId: 'competing-writer', kind: 'autosave',
      accountId: 'alpha', documentId: 'draft-a', baseRevision: 0,
      payload: { title: 'Other writer', notes: 'Their revision must survive.' }
    })
  });
  assert.equal(competing.status, 200);
  client.input('notes', 'Stale data');
  client.submit();
  await until(() => client.state === 'refused');
  assert.equal(client.requests.length, 1);
  assert.equal(client.storage.size, 0);
  const state = await readOracle(fixture);
  assert.equal(state.documents[0].notes, 'Their revision must survive.');
  assert.equal(state.documents[0].submissionCount, 0);
});

test('a mismatched successful response is UNKNOWN even when the provider committed', async t => {
  const fixture = await fixtureFor(t);
  const client = await mount(fixture, {
    intercept: async ({ send }) => {
      const actual = await send();
      const receipt = await actual.json();
      return { ok: true, json: async () => ({ ...receipt, operationId: 'some-other-operation' }) };
    }
  });
  client.input('notes', 'Commit with a corrupted response identity.');
  await until(() => client.state === 'unknown');
  assert.equal(client.requests.length, 1);
  assert.equal(client.storage.size, 1);
  assert.equal((await readOracle(fixture)).operations.length, 1);
});

test('an operation persisted before dispatch remains UNKNOWN when another page instance loads', async t => {
  const fixture = await fixtureFor(t);
  const storage = new Map();
  let release;
  const held = new Promise(resolve => { release = resolve; });
  const first = await mount(fixture, {
    storage,
    intercept: async ({ send }) => { await held; return send(); }
  });
  first.input('notes', 'Request waiting for transport.');
  assert.equal(JSON.parse([...storage.values()][0]).state, 'pending');
  const second = await mount(fixture, { storage });
  assert.equal(second.state, 'unknown');
  assert.equal(second.idsCreated, 0);
  assert.equal(second.requests.length, 0);
  release();
  await until(() => first.state === 'saved');
  second.submit();
  assert.equal(second.requests.length, 0);
});

test('unavailable operation storage blocks dispatch instead of losing recovery identity', async t => {
  const fixture = await fixtureFor(t);
  const client = await mount(fixture, {
    storageOverride: {
      getItem: () => null,
      setItem() { throw new Error('Storage unavailable'); },
      removeItem() {}
    }
  });
  client.input('notes', 'Must not leave without a recorded identity.');
  await until(() => client.state === 'blocked');
  assert.equal(client.requests.length, 0);
  assert.equal(client.idsCreated, 0);
  for (const id of ['title', 'notes', 'submit-button']) assert.equal(client.elements.get(id).disabled, true);
  assert.equal((await readOracle(fixture)).operations.length, 0);
});

test('unreadable recovery state leaves every form control disabled at initialization', async t => {
  const fixture = await fixtureFor(t);
  const client = await mount(fixture, {
    storageOverride: {
      getItem() { throw new Error('Storage access denied'); },
      setItem() { assert.fail('Must not write after unreadable recovery state'); },
      removeItem() { assert.fail('Must not remove unreadable recovery state'); }
    }
  });
  assert.equal(client.state, 'blocked');
  for (const id of ['title', 'notes', 'submit-button']) assert.equal(client.elements.get(id).disabled, true);
  client.input('notes', 'Cannot create an untracked early effect.');
  client.submit();
  assert.equal(client.idsCreated, 0);
  assert.equal(client.requests.length, 0);
  assert.equal((await readOracle(fixture)).operations.length, 0);
});

test('unavailable secure randomness fails visibly before dispatch', async t => {
  const fixture = await fixtureFor(t);
  const client = await mount(fixture, { cryptoOverride: {} });
  client.input('notes', 'No reliable operation identity is available.');
  await until(() => client.state === 'blocked');
  assert.equal(client.idsCreated, 0);
  assert.equal(client.requests.length, 0);
  assert.equal(client.elements.get('submit-button').disabled, true);
  assert.match(client.elements.get('status').textContent, /Nothing was sent/);
  assert.equal((await readOracle(fixture)).operations.length, 0);
});
