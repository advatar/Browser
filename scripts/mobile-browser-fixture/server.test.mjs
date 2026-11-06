import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { startFixture } from './server.mjs';

async function fixtureFor(testContext, options) {
  const fixture = await startFixture({ port: 0, ...options });
  testContext.after(() => fixture.close());
  return fixture;
}

function operation(fixture, overrides = {}) {
  return {
    fixtureId: fixture.fixtureId, operationId: 'operation-1', kind: 'autosave',
    accountId: 'alpha', documentId: 'draft-a', baseRevision: 0,
    payload: { title: 'Cedar workshop', notes: 'Room Delta at 10:00; aisle seat and decaf.' },
    ...overrides
  };
}

function post(fixture, body) {
  return fetch(`${fixture.url}/api/operations`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
  });
}

async function oracle(fixture) {
  const response = await fetch(`${fixture.url}/oracle`, { headers: { Authorization: `Bearer ${fixture.oracleToken}` } });
  assert.equal(response.status, 200);
  return response.json();
}

test('serves two synthetic sources, distinct documents and bounded mobile assets over HTTP', async t => {
  const fixture = await fixtureFor(t);
  for (const path of ['/', '/sources/one', '/sources/two', '/drafts/alpha/draft-a', '/drafts/beta/draft-b']) {
    const response = await fetch(`${fixture.url}${path}`);
    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type'), /text\/html/);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    const body = await response.text();
    assert.match(body, /name="viewport"/);
    assert.match(body, /Synthetic local browser fixture/);
    assert.ok(!body.includes(fixture.oracleToken));
    if (path.startsWith('/drafts/')) {
      assert.match(body, /<input\b[^>]*\bid="title"[^>]*\bdisabled\b/);
      assert.match(body, /<textarea\b[^>]*\bid="notes"[^>]*\bdisabled\b/);
      assert.match(body, /<button\b[^>]*\bid="submit-button"[^>]*\bdisabled\b/);
    }
  }
  for (const path of ['/client.js', '/styles.css']) {
    const response = await fetch(`${fixture.url}${path}`);
    assert.equal(response.status, 200);
    assert.ok(!(await response.text()).includes(fixture.oracleToken));
  }
  const alpha = await (await fetch(`${fixture.url}/api/documents/alpha/draft-a`)).json();
  const beta = await (await fetch(`${fixture.url}/api/documents/beta/draft-b`)).json();
  assert.equal(alpha.fixtureId, fixture.fixtureId);
  assert.equal(alpha.document.revision, 0);
  assert.equal(beta.document.accountId, 'beta');
  assert.equal((await fetch(`${fixture.url}/api/documents/alpha/draft-b`)).status, 404);
  assert.equal((await fetch(`${fixture.url}/?reset=true`)).status, 400);
  assert.equal((await fetch(`${fixture.url}/admin/reset`, { method: 'POST' })).status, 405);
});

test('autosave commits before separate submission and exact replay returns the original receipt', async t => {
  const fixture = await fixtureFor(t);
  const save = operation(fixture);
  const saveResponse = await post(fixture, save);
  assert.equal(saveResponse.status, 200);
  const saved = await saveResponse.json();
  assert.equal(saved.revision, 1);
  let state = await oracle(fixture);
  assert.equal(state.documents[0].autosaveCount, 1);
  assert.equal(state.documents[0].submissionCount, 0);
  assert.equal(state.documents[0].submitted, false);
  assert.equal(state.documents[0].notes, save.payload.notes);

  const submit = operation(fixture, { operationId: 'submit-1', kind: 'submit', baseRevision: 1 });
  const submitted = await (await post(fixture, submit)).json();
  assert.equal(submitted.document.submissionCount, 1);
  assert.equal(submitted.revision, 2);
  // Even after later document changes, idempotency lookup precedes stale-revision checks.
  assert.deepEqual(await (await post(fixture, save)).json(), saved);
  assert.deepEqual(await (await post(fixture, submit)).json(), submitted);
  state = await oracle(fixture);
  assert.equal(state.operations.length, 2);
  assert.equal(state.documents[0].revision, 2);
  assert.equal(state.documents[0].submissionCount, 1);
  const afterSubmit = await post(fixture, operation(fixture, { operationId: 'after-submit', baseRevision: 2 }));
  assert.equal(afterSubmit.status, 409);
  assert.equal((await afterSubmit.json()).error.code, 'DOCUMENT_SUBMITTED');
});

test('a committed operation ID cannot change kind, account, document, revision or exact payload', async t => {
  const fixture = await fixtureFor(t);
  const first = operation(fixture);
  assert.equal((await post(fixture, first)).status, 200);
  for (const change of [
    { kind: 'submit' },
    { accountId: 'beta' },
    { documentId: 'draft-b' },
    { accountId: 'beta', documentId: 'draft-b' },
    { baseRevision: 1 },
    { payload: { ...first.payload, title: `${first.payload.title} ` } },
    { payload: { ...first.payload, notes: 'different exact notes' } }
  ]) {
    const response = await post(fixture, { ...first, ...change });
    assert.equal(response.status, 409);
    assert.equal((await response.json()).error.code, 'OPERATION_CONFLICT');
  }
  const state = await oracle(fixture);
  assert.equal(state.operations.length, 1);
  assert.equal(state.documents[1].revision, 0);
});

test('stale revisions refuse mutations and simultaneous requests cannot both consume one revision', async t => {
  const fixture = await fixtureFor(t);
  const responses = await Promise.all([
    post(fixture, operation(fixture, { operationId: 'writer-one' })),
    post(fixture, operation(fixture, { operationId: 'writer-two', payload: { title: 'Other writer', notes: 'Other notes' } }))
  ]);
  assert.deepEqual(responses.map(response => response.status).sort(), [200, 409]);
  const failed = await responses.find(response => response.status === 409).json();
  assert.equal(failed.error.code, 'STALE_REVISION');
  const stale = await post(fixture, operation(fixture, { operationId: 'stale-submit', kind: 'submit' }));
  assert.equal(stale.status, 409);
  assert.equal((await stale.json()).error.code, 'STALE_REVISION');
  const state = await oracle(fixture);
  assert.equal(state.operations.length, 1);
  assert.equal(state.documents[0].autosaveCount, 1);
  assert.equal(state.documents[0].submissionCount, 0);
});

test('simultaneous exact replays record one commit', async t => {
  const fixture = await fixtureFor(t);
  const body = operation(fixture);
  const receipts = await Promise.all(Array.from({ length: 8 }, async () => {
    const response = await post(fixture, body);
    assert.equal(response.status, 200);
    return response.json();
  }));
  for (const receipt of receipts) assert.deepEqual(receipt, receipts[0]);
  const state = await oracle(fixture);
  assert.equal(state.operations.length, 1);
  assert.equal(state.documents[0].revision, 1);
});

test('one-shot response loss happens after commit; only an explicit exact replay recovers it', async t => {
  const fixture = await fixtureFor(t, { dropResponseAfterCommit: 'submit' });
  assert.equal((await post(fixture, operation(fixture))).status, 200);
  const submit = operation(fixture, { operationId: 'lost-submit', kind: 'submit', baseRevision: 1 });
  await assert.rejects(post(fixture, submit), /fetch failed/);
  const afterLoss = await oracle(fixture);
  assert.equal(afterLoss.documents[0].submissionCount, 1);
  assert.equal(afterLoss.operations.length, 2);
  assert.deepEqual(afterLoss.fault, { kind: 'submit', armed: false, droppedResponses: 1 });
  const recovered = await post(fixture, submit);
  assert.equal(recovered.status, 200);
  assert.deepEqual(await recovered.json(), afterLoss.operations[1].receipt);
  assert.equal((await post(fixture, operation(fixture, {
    operationId: 'second-account-submit', kind: 'submit', accountId: 'beta', documentId: 'draft-b'
  }))).status, 200);
  const finalState = await oracle(fixture);
  assert.equal(finalState.fault.droppedResponses, 1);
  assert.equal(finalState.documents[0].submissionCount, 1);
  assert.equal(finalState.documents[1].submissionCount, 1);
});

test('oracle requires its separate token, is read-only, and does not reveal that token', async t => {
  const fixture = await fixtureFor(t);
  for (const headers of [{}, { Authorization: 'Bearer wrong-token' }, { Authorization: `Bearer ${'x'.repeat(64)}` }]) {
    assert.equal((await fetch(`${fixture.url}/oracle`, { headers })).status, 401);
  }
  for (const method of ['POST', 'PUT', 'DELETE', 'PATCH']) {
    const response = await fetch(`${fixture.url}/oracle`, {
      method, headers: { Authorization: `Bearer ${fixture.oracleToken}` }
    });
    assert.equal(response.status, 405);
    assert.equal((await response.json()).error.code, 'READ_ONLY_ORACLE');
  }
  const state = await oracle(fixture);
  assert.ok(!JSON.stringify(state).includes(fixture.oracleToken));
  assert.equal(state.operations.length, 0);
});

test('invalid and oversized input cannot commit; a full ledger preserves existing replay records', async t => {
  const fixture = await fixtureFor(t, { maxOperations: 1 });
  const malformed = await fetch(`${fixture.url}/api/operations`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{'
  });
  assert.equal(malformed.status, 400);
  assert.equal((await post(fixture, { ...operation(fixture), extra: true })).status, 400);
  assert.equal((await post(fixture, operation(fixture, { baseRevision: -1 }))).status, 400);
  assert.equal((await post(fixture, operation(fixture, { payload: { title: 'x'.repeat(121), notes: '' } }))).status, 400);
  assert.equal((await post(fixture, operation(fixture, { payload: { title: 'a', notes: 'x'.repeat(2_001) } }))).status, 400);
  const oversized = await fetch(`${fixture.url}/api/operations`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ filler: 'x'.repeat(9_000) })
  });
  assert.equal(oversized.status, 413);
  const wrongType = await fetch(`${fixture.url}/api/operations`, {
    method: 'POST', body: 'title=hello'
  });
  assert.equal(wrongType.status, 415);
  const crossOrigin = await fetch(`${fixture.url}/api/operations`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Origin: 'https://example.invalid' },
    body: JSON.stringify(operation(fixture))
  });
  assert.equal(crossOrigin.status, 403);
  assert.equal((await oracle(fixture)).operations.length, 0);
  const original = await (await post(fixture, operation(fixture))).json();
  const full = await post(fixture, operation(fixture, { operationId: 'over-capacity', baseRevision: 1 }));
  assert.equal(full.status, 503);
  assert.equal((await full.json()).error.code, 'CAPACITY');
  assert.deepEqual(await (await post(fixture, operation(fixture))).json(), original);
  assert.equal((await oracle(fixture)).operations.length, 1);
});

test('fixture runs isolate state and old-run operations cannot be applied to a new run', async t => {
  const first = await fixtureFor(t);
  const second = await fixtureFor(t);
  assert.notEqual(first.fixtureId, second.fixtureId);
  assert.equal((await post(first, operation(first))).status, 200);
  const oldRun = await post(second, operation(first));
  assert.equal(oldRun.status, 409);
  assert.equal((await oldRun.json()).error.code, 'WRONG_FIXTURE');
  const state = await oracle(second);
  assert.equal(state.operations.length, 0);
  assert.equal(state.documents[0].revision, 0);
  await second.close();
  await second.close();
});

test('a wrong Host header is refused over actual HTTP before mutation', async t => {
  const fixture = await fixtureFor(t);
  const body = JSON.stringify(operation(fixture));
  const result = await new Promise((resolve, reject) => {
    const request = http.request(`${fixture.url}/api/operations`, {
      method: 'POST', headers: {
        Host: 'wrong-host.invalid', 'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    }, response => {
      let text = '';
      response.setEncoding('utf8');
      response.on('data', chunk => { text += chunk; });
      response.on('error', reject);
      response.on('end', () => resolve({ status: response.statusCode, body: JSON.parse(text) }));
    });
    request.on('error', reject);
    request.end(body);
  });
  assert.equal(result.status, 421);
  assert.equal(result.body.error.code, 'WRONG_HOST');
  assert.equal((await oracle(fixture)).operations.length, 0);
});

test('stored markup round-trips as data and cannot break out of title attributes or textarea content', async t => {
  const fixture = await fixtureFor(t);
  const payload = {
    title: '\" autofocus onfocus=\"alert(1)\" <tag>&\'',
    notes: '</textarea><script>notExecuted()</script>&\"\''
  };
  const response = await post(fixture, operation(fixture, { payload }));
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).payload, payload);
  const current = await (await fetch(`${fixture.url}/api/documents/alpha/draft-a`)).json();
  assert.equal(current.document.title, payload.title);
  assert.equal(current.document.notes, payload.notes);
  const rendered = await (await fetch(`${fixture.url}/drafts/alpha/draft-a`)).text();
  assert.ok(rendered.includes('value="&quot; autofocus onfocus=&quot;alert(1)&quot; &lt;tag&gt;&amp;&#39;"'));
  assert.ok(rendered.includes('&lt;/textarea&gt;&lt;script&gt;notExecuted()&lt;/script&gt;&amp;&quot;&#39;'));
  assert.ok(!rendered.includes('<script>notExecuted()'));
  assert.ok(!rendered.includes('value="" autofocus'));
});
