import http from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { isIP } from 'node:net';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';

const MAX_BODY_BYTES = 8_192;
const MAX_TITLE_LENGTH = 120;
const MAX_NOTES_LENGTH = 2_000;
const DOCUMENTS = [
  { accountId: 'alpha', documentId: 'draft-a', title: 'Workshop brief', notes: '' },
  { accountId: 'beta', documentId: 'draft-b', title: 'Second account draft', notes: '' }
];
const SOURCES = {
  one: {
    title: 'Source A: workshop schedule',
    content: '<p>The fictional Cedar workshop starts at <strong>10:00 on Tuesday</strong> in <strong>Room Delta</strong>. The room has twelve seats.</p>'
  },
  two: {
    title: 'Source B: participant preferences',
    content: '<p>The fictional participant prefers an <strong>aisle seat</strong> and <strong>decaf coffee</strong>. Their brief should include the room and starting time and stay below eighty words.</p>'
  }
};

class FixtureError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

function html(value) {
  return String(value).replace(/[&<>"']/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  })[character]);
}

function page(title, content, { script = false } = {}) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${html(title)} · mobile browser fixture</title><link rel="stylesheet" href="/styles.css">
${script ? '<script src="/client.js" defer></script>' : ''}</head>
<body><main><p class="eyebrow">Synthetic local browser fixture</p><h1>${html(title)}</h1>
${content}<footer>This is disposable test data. No real service, account or transaction is connected.</footer></main></body></html>`;
}

function documentSnapshot(document) {
  return {
    accountId: document.accountId,
    documentId: document.documentId,
    revision: document.revision,
    title: document.title,
    notes: document.notes,
    submitted: document.submitted,
    autosaveCount: document.autosaveCount,
    submissionCount: document.submissionCount
  };
}

function draftPage(document, fixtureId) {
  return page('Prepare the workshop brief', `
<p>Read both sources, combine their details in this draft, then submit it.</p>
<nav aria-label="Task sources"><a id="source-one" href="/sources/one">Read source A</a><a id="source-two" href="/sources/two">Read source B</a><a href="/">Fixture home</a></nav>
<p class="notice"><strong>Typing saves immediately.</strong> Input events save changes to this fixture before submission. A lost response leaves the operation uncertain and stops further changes.</p>
<p>Account: <strong id="account">${html(document.accountId)}</strong> · Document: <strong id="document">${html(document.documentId)}</strong> · Revision: <strong id="revision">${document.revision}</strong></p>
<form id="draft-form" data-fixture-id="${fixtureId}" data-account-id="${document.accountId}" data-document-id="${document.documentId}" data-revision="${document.revision}" data-submitted="${document.submitted}" action="/api/operations" method="post">
<label for="title">Brief title</label><input id="title" name="title" maxlength="${MAX_TITLE_LENGTH}" value="${html(document.title)}" autocomplete="off" disabled>
<label for="notes">Brief notes</label><textarea id="notes" name="notes" maxlength="${MAX_NOTES_LENGTH}" rows="7" disabled>${html(document.notes)}</textarea>
<button id="submit-button" type="submit" disabled>Submit brief</button></form>
<p id="status" role="status" aria-live="polite" data-state="loading">Preparing the form…</p>
<p>Last operation: <code id="operation">None</code></p><pre id="receipt" aria-label="Acknowledged fixture result"></pre>
<noscript>This task requires JavaScript for autosave and operation tracking.</noscript>`, { script: true });
}

function sameKeys(value, keys) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).sort().join(',') === [...keys].sort().join(',');
}

function validateOperation(value) {
  const required = ['fixtureId', 'operationId', 'kind', 'accountId', 'documentId', 'baseRevision', 'payload'];
  if (!sameKeys(value, required)
      || typeof value.fixtureId !== 'string' || !/^[a-f0-9]{32}$/.test(value.fixtureId)
      || typeof value.operationId !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(value.operationId)
      || !['autosave', 'submit'].includes(value.kind)
      || typeof value.accountId !== 'string' || !/^[a-z][a-z0-9-]{0,39}$/.test(value.accountId)
      || typeof value.documentId !== 'string' || !/^[a-z][a-z0-9-]{0,39}$/.test(value.documentId)
      || !Number.isSafeInteger(value.baseRevision) || value.baseRevision < 0
      || !sameKeys(value.payload, ['title', 'notes'])
      || typeof value.payload.title !== 'string' || value.payload.title.length > MAX_TITLE_LENGTH
      || typeof value.payload.notes !== 'string' || value.payload.notes.length > MAX_NOTES_LENGTH) {
    throw new FixtureError(400, 'INVALID_REQUEST', 'Expected one bounded, exact fixture operation.');
  }
  return value;
}

function operationIdentity(operation) {
  // Fixed field ordering preserves exact values without depending on JSON key order.
  return JSON.stringify([
    operation.fixtureId, operation.kind, operation.accountId, operation.documentId,
    operation.baseRevision, operation.payload.title, operation.payload.notes
  ]);
}

function readJSON(request) {
  if (request.headers['content-type']?.split(';', 1)[0].trim().toLowerCase() !== 'application/json') {
    request.resume();
    throw new FixtureError(415, 'INVALID_CONTENT_TYPE', 'Use application/json.');
  }
  return new Promise((resolveBody, reject) => {
    let bytes = 0;
    let chunks = [];
    let settled = false;
    const fail = error => {
      if (settled) return;
      settled = true;
      chunks = [];
      reject(error);
    };
    request.on('data', chunk => {
      if (settled) return;
      bytes += chunk.length;
      if (bytes > MAX_BODY_BYTES) {
        fail(new FixtureError(413, 'BODY_TOO_LARGE', 'Request body exceeds the fixture limit.'));
      } else {
        chunks.push(chunk);
      }
    });
    request.on('aborted', () => fail(new FixtureError(400, 'INVALID_REQUEST', 'Request was interrupted.')));
    request.on('error', fail);
    request.on('end', () => {
      if (settled) return;
      settled = true;
      try {
        resolveBody(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        reject(new FixtureError(400, 'INVALID_REQUEST', 'Request body must be JSON.'));
      }
      chunks = [];
    });
  });
}

function send(response, status, value, contentType = 'application/json; charset=utf-8') {
  const body = contentType.startsWith('application/json') ? JSON.stringify(value) : value;
  response.writeHead(status, {
    'Content-Type': contentType,
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
  });
  response.end(body);
}

/**
 * Start a disposable fixture. State and idempotency exist only for this process/run.
 * The oracle is test instrumentation, not a production authority or signed verifier.
 */
export async function startFixture({
  port = 0,
  host = '127.0.0.1',
  oracleToken = randomBytes(32).toString('hex'),
  maxOperations = 128,
  dropResponseAfterCommit = null
} = {}) {
  if (!Number.isInteger(port) || port < 0 || port > 65_535
      || !(isIP(host) || host === 'localhost')
      || typeof oracleToken !== 'string' || !/^[A-Za-z0-9_-]{32,128}$/.test(oracleToken)
      || !Number.isInteger(maxOperations) || maxOperations < 1 || maxOperations > 1_000
      || ![null, 'autosave', 'submit'].includes(dropResponseAfterCommit)) {
    throw new TypeError('Invalid fixture options.');
  }
  const [clientScript, styleSheet] = await Promise.all([
    readFile(new URL('./client.js', import.meta.url), 'utf8'),
    readFile(new URL('./styles.css', import.meta.url), 'utf8')
  ]);
  const fixtureId = randomBytes(16).toString('hex');
  const documents = new Map(DOCUMENTS.map(document => [
    `${document.accountId}/${document.documentId}`,
    { ...document, revision: 0, submitted: false, autosaveCount: 0, submissionCount: 0 }
  ]));
  const operations = new Map();
  let dropArmed = dropResponseAfterCommit !== null;
  let droppedResponses = 0;
  let url;

  function commit(operation) {
    if (operation.fixtureId !== fixtureId) {
      throw new FixtureError(409, 'WRONG_FIXTURE', 'This operation belongs to another fixture run.');
    }
    const identity = operationIdentity(operation);
    const existing = operations.get(operation.operationId);
    if (existing) {
      if (existing.identity !== identity) {
        throw new FixtureError(409, 'OPERATION_CONFLICT', 'The operation ID already identifies different input.');
      }
      return { receipt: existing.receipt, newCommit: false };
    }
    const document = documents.get(`${operation.accountId}/${operation.documentId}`);
    if (!document) throw new FixtureError(404, 'UNKNOWN_DOCUMENT', 'No such synthetic account/document pair.');
    if (document.revision !== operation.baseRevision) {
      throw new FixtureError(409, 'STALE_REVISION', 'The document changed; the stale operation was refused.');
    }
    if (document.submitted) {
      throw new FixtureError(409, 'DOCUMENT_SUBMITTED', 'This fixture document is already submitted.');
    }
    if (operations.size >= maxOperations) {
      throw new FixtureError(503, 'CAPACITY', 'The fixture operation ledger is full; no records were evicted.');
    }
    if (operation.kind === 'submit' && operation.payload.title.trim().length === 0) {
      throw new FixtureError(422, 'EMPTY_TITLE', 'A submitted brief needs a title.');
    }
    // No awaits occur between revision validation and recording the effect.
    document.title = operation.payload.title;
    document.notes = operation.payload.notes;
    document.revision += 1;
    if (operation.kind === 'autosave') document.autosaveCount += 1;
    else {
      document.submitted = true;
      document.submissionCount += 1;
    }
    const receipt = {
      status: 'committed', fixtureId, operationId: operation.operationId,
      kind: operation.kind, accountId: operation.accountId, documentId: operation.documentId,
      baseRevision: operation.baseRevision, revision: document.revision,
      payload: { ...operation.payload }, document: documentSnapshot(document)
    };
    operations.set(operation.operationId, { identity, operation, receipt });
    return { receipt, newCommit: true };
  }

  const server = http.createServer(async (request, response) => {
    try {
      if (request.headers.host?.toLowerCase() !== new URL(url).host.toLowerCase()) {
        throw new FixtureError(421, 'WRONG_HOST', 'Use the fixture address printed at startup.');
      }
      const target = new URL(request.url, url);
      if (target.search || target.hash) throw new FixtureError(400, 'INVALID_REQUEST', 'This fixture has no query commands.');
      const pathname = target.pathname;
      if (pathname === '/oracle') {
        const supplied = request.headers.authorization;
        const expected = `Bearer ${oracleToken}`;
        if (typeof supplied !== 'string' || Buffer.byteLength(supplied) !== Buffer.byteLength(expected)
            || !timingSafeEqual(Buffer.from(supplied), Buffer.from(expected))) {
          throw new FixtureError(401, 'ORACLE_AUTH_REQUIRED', 'A separate fixture oracle token is required.');
        }
        if (request.method !== 'GET') throw new FixtureError(405, 'READ_ONLY_ORACLE', 'The oracle is read-only.');
        return send(response, 200, {
          fixtureId,
          documents: [...documents.values()].map(documentSnapshot),
          operations: [...operations.values()].map(({ operation, receipt }) => ({ operation, receipt })),
          fault: { kind: dropResponseAfterCommit, armed: dropArmed, droppedResponses },
          limits: { maxOperations, maxBodyBytes: MAX_BODY_BYTES, maxTitleLength: MAX_TITLE_LENGTH, maxNotesLength: MAX_NOTES_LENGTH },
          persistence: 'in-memory; reset on fixture restart'
        });
      }
      if (pathname === '/api/operations') {
        if (request.method !== 'POST') throw new FixtureError(405, 'METHOD_NOT_ALLOWED', 'POST an exact operation.');
        if (request.headers.origin && request.headers.origin !== new URL(url).origin) {
          throw new FixtureError(403, 'CROSS_ORIGIN_REQUEST', 'Cross-origin mutations are unavailable.');
        }
        const operation = validateOperation(await readJSON(request));
        const result = commit(operation);
        if (result.newCommit && dropArmed && operation.kind === dropResponseAfterCommit) {
          dropArmed = false;
          droppedResponses += 1;
          // Deliberately lose acknowledgement only after the ledger and document commit.
          response.destroy();
          return;
        }
        return send(response, 200, result.receipt);
      }
      if (request.method !== 'GET') throw new FixtureError(405, 'METHOD_NOT_ALLOWED', 'This route is read-only.');
      if (pathname === '/client.js') return send(response, 200, clientScript, 'text/javascript; charset=utf-8');
      if (pathname === '/styles.css') return send(response, 200, styleSheet, 'text/css; charset=utf-8');
      if (pathname === '/') {
        return send(response, 200, page('Mobile browser task', `
<p>Read two synthetic sources, prepare a brief and submit it. The provider ledger records autosaves and submissions separately.</p>
<nav aria-label="Sources"><a href="/sources/one">Source A: workshop schedule</a><a href="/sources/two">Source B: participant preferences</a></nav>
<h2>Choose a synthetic account</h2><ul><li><a id="open-alpha" href="/drafts/alpha/draft-a">Alpha · draft A</a></li><li><a id="open-beta" href="/drafts/beta/draft-b">Beta · draft B</a></li></ul>
<p class="notice">State exists only for this fixture run. Server tests do not qualify native iPhone browser execution.</p>`), 'text/html; charset=utf-8');
      }
      const source = /^\/sources\/(one|two)$/.exec(pathname);
      if (source) {
        const content = SOURCES[source[1]];
        return send(response, 200, page(content.title, `${content.content}<nav><a href="/drafts/alpha/draft-a">Open Alpha draft</a><a href="/drafts/beta/draft-b">Open Beta draft</a><a href="/">Fixture home</a></nav>`), 'text/html; charset=utf-8');
      }
      const documentRoute = /^\/(drafts|api\/documents)\/([a-z][a-z0-9-]{0,39})\/([a-z][a-z0-9-]{0,39})$/.exec(pathname);
      if (documentRoute) {
        const document = documents.get(`${documentRoute[2]}/${documentRoute[3]}`);
        if (!document) throw new FixtureError(404, 'UNKNOWN_DOCUMENT', 'No such synthetic account/document pair.');
        if (documentRoute[1] === 'api/documents') return send(response, 200, { fixtureId, document: documentSnapshot(document) });
        return send(response, 200, draftPage(document, fixtureId), 'text/html; charset=utf-8');
      }
      throw new FixtureError(404, 'NOT_FOUND', 'No such fixture route.');
    } catch (error) {
      if (!response.destroyed && !response.headersSent) {
        send(response, error instanceof FixtureError ? error.status : 500, {
          error: { code: error instanceof FixtureError ? error.code : 'INTERNAL_ERROR', message: error instanceof FixtureError ? error.message : 'The fixture could not complete the request.' }
        });
      }
    }
  });
  server.maxConnections = 32;
  server.maxHeadersCount = 32;
  server.requestTimeout = 5_000;
  server.headersTimeout = 5_000;
  server.keepAliveTimeout = 1_000;
  await new Promise((resolveListen, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => {
      server.removeListener('error', reject);
      resolveListen();
    });
  });
  const address = server.address();
  url = `http://${isIP(host) === 6 ? `[${host}]` : host}:${address.port}`;
  let closing;
  return {
    url,
    fixtureId,
    oracleToken,
    close() {
      closing ??= new Promise((resolveClose, reject) => {
        server.close(error => error ? reject(error) : resolveClose());
        server.closeAllConnections();
      });
      return closing;
    }
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const { values } = parseArgs({
      options: {
        host: { type: 'string', default: '127.0.0.1' },
        port: { type: 'string', default: '4877' },
        'max-operations': { type: 'string', default: '128' },
        'drop-response-after-commit': { type: 'string' },
        help: { type: 'boolean', short: 'h' }
      },
      allowPositionals: false
    });
    if (values.help) {
      process.stdout.write('Usage: node scripts/mobile-browser-fixture/server.mjs [--host 127.0.0.1] [--port 4877] [--max-operations 128] [--drop-response-after-commit autosave|submit]\n');
    } else {
      const fixture = await startFixture({
        host: values.host,
        port: Number(values.port),
        maxOperations: Number(values['max-operations']),
        dropResponseAfterCommit: values['drop-response-after-commit'] ?? null
      });
      process.stdout.write(`Fixture: ${fixture.url}\nOracle: ${fixture.url}/oracle\n`);
      process.stderr.write(`Local fixture oracle bearer token (test instrumentation only): ${fixture.oracleToken}\n`);
      const stop = () => { void fixture.close(); };
      process.once('SIGINT', stop);
      process.once('SIGTERM', stop);
    }
  } catch (error) {
    process.stderr.write(`Fixture could not start: ${error.message}\n`);
    process.exitCode = 1;
  }
}
