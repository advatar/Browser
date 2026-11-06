(() => {
  'use strict';

  const form = document.getElementById('draft-form');
  if (!form) return;
  const title = document.getElementById('title');
  const notes = document.getElementById('notes');
  const submit = document.getElementById('submit-button');
  const status = document.getElementById('status');
  const revisionLabel = document.getElementById('revision');
  const operationLabel = document.getElementById('operation');
  const receiptLabel = document.getElementById('receipt');
  const { fixtureId, accountId, documentId } = form.dataset;
  const storageKey = `mobile-browser-fixture:${fixtureId}:${accountId}:${documentId}`;
  let revision = Number(form.dataset.revision);
  let saved = { title: title.value, notes: notes.value };
  let desired = { ...saved };
  let running = false;
  let halted = false;
  let submitRequested = false;
  let currentOperation = null;
  const knownRefusals = new Set([
    'INVALID_REQUEST', 'INVALID_CONTENT_TYPE', 'BODY_TOO_LARGE', 'WRONG_FIXTURE',
    'OPERATION_CONFLICT', 'UNKNOWN_DOCUMENT', 'STALE_REVISION', 'DOCUMENT_SUBMITTED',
    'CAPACITY', 'EMPTY_TITLE', 'CROSS_ORIGIN_REQUEST', 'WRONG_HOST'
  ]);

  function show(state, message) {
    status.dataset.state = state;
    status.textContent = message;
  }

  function lock() {
    title.disabled = true;
    notes.disabled = true;
    submit.disabled = true;
  }

  function samePayload(left, right) {
    return left.title === right.title && left.notes === right.notes;
  }

  function remember(state, operation) {
    sessionStorage.setItem(storageKey, JSON.stringify({ state, operation }));
  }

  function uncertain(message) {
    halted = true;
    lock();
    if (currentOperation) {
      operationLabel.textContent = currentOperation.operationId;
      try { remember('unknown', currentOperation); } catch { /* Keep the original in memory and stop. */ }
    }
    show('unknown', `UNKNOWN: ${message} No retry was sent. Keep this operation ID for the separate fixture oracle.`);
  }

  function matchesReceipt(receipt, operation) {
    return receipt?.status === 'committed'
      && receipt.fixtureId === operation.fixtureId
      && receipt.operationId === operation.operationId
      && receipt.kind === operation.kind
      && receipt.accountId === operation.accountId
      && receipt.documentId === operation.documentId
      && receipt.baseRevision === operation.baseRevision
      && receipt.revision === operation.baseRevision + 1
      && receipt.payload && samePayload(receipt.payload, operation.payload);
  }

  async function perform(kind, payload) {
    let operation;
    try {
      // getRandomValues also works on a device's explicit HTTP development origin.
      const bytes = crypto.getRandomValues(new Uint8Array(16));
      const operationId = Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
      operation = {
        fixtureId, operationId, kind, accountId, documentId,
        baseRevision: revision, payload: { ...payload }
      };
      currentOperation = operation;
      operationLabel.textContent = operation.operationId;
      // Persist before dispatch. Reloading a pending attempt must never make a new ID.
      remember('pending', operation);
    } catch {
      halted = true;
      lock();
      show('blocked', 'Operation identity or recovery tracking is unavailable. Nothing was sent.');
      return false;
    }
    show(kind === 'autosave' ? 'saving' : 'submitting', kind === 'autosave' ? 'Saving typed changes…' : 'Submitting the saved brief…');
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5_000);
    try {
      const response = await fetch('/api/operations', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(operation),
        signal: controller.signal
      });
      const result = await response.json();
      if (!response.ok) {
        if (!knownRefusals.has(result?.error?.code)) {
          uncertain('The provider did not return a recognized result.');
          return false;
        }
        sessionStorage.removeItem(storageKey);
        halted = true;
        lock();
        show('refused', `Refused: ${result.error.message} No retry was sent.`);
        return false;
      }
      if (!matchesReceipt(result, operation)) {
        uncertain('The response does not match this exact operation.');
        return false;
      }
      sessionStorage.removeItem(storageKey);
      revision = result.revision;
      revisionLabel.textContent = String(revision);
      saved = { ...payload };
      receiptLabel.textContent = JSON.stringify(result, null, 2);
      show(kind === 'autosave' ? 'saved' : 'submitted', kind === 'autosave' ? `Saved revision ${revision}. Submission is still separate.` : `Fixture submission acknowledged at revision ${revision}.`);
      return true;
    } catch {
      uncertain('The response was lost, interrupted or unreadable; the provider may have committed.');
      return false;
    } finally {
      clearTimeout(timeout);
    }
  }

  async function drain() {
    if (running || halted) return;
    running = true;
    try {
      while (!halted) {
        if (!samePayload(saved, desired)) {
          if (!await perform('autosave', { ...desired })) break;
          continue;
        }
        if (submitRequested) {
          if (await perform('submit', { ...saved })) {
            halted = true;
            lock();
          }
        }
        break;
      }
    } finally {
      running = false;
    }
  }

  function input() {
    if (halted || submitRequested) return;
    desired = { title: title.value, notes: notes.value };
    void drain();
  }

  title.addEventListener('input', input);
  notes.addEventListener('input', input);
  form.addEventListener('submit', event => {
    event.preventDefault();
    if (halted || submitRequested) return;
    desired = { title: title.value, notes: notes.value };
    submitRequested = true;
    lock();
    void drain();
  });

  lock();
  try {
    const stored = sessionStorage.getItem(storageKey);
    if (stored !== null) {
      if (stored.length > 8_192) throw new Error('Stored operation exceeds the fixture limit.');
      const pending = JSON.parse(stored);
      if (pending?.operation?.fixtureId === fixtureId
          && pending.operation.accountId === accountId
          && pending.operation.documentId === documentId
          && typeof pending.operation.operationId === 'string'
          && /^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(pending.operation.operationId)) {
        currentOperation = pending.operation;
      }
      uncertain('This page has a previous unacknowledged operation. Reloading does not replay it.');
    } else if (form.dataset.submitted === 'true') {
      halted = true;
      lock();
      show('submitted', 'This fixture document is already submitted.');
    } else {
      if (typeof crypto?.getRandomValues !== 'function') throw new Error('Randomness unavailable.');
      const probeKey = `${storageKey}:storage-check`;
      sessionStorage.setItem(probeKey, 'ready');
      if (sessionStorage.getItem(probeKey) !== 'ready') throw new Error('Recovery tracking unavailable.');
      sessionStorage.removeItem(probeKey);
      title.disabled = false;
      notes.disabled = false;
      submit.disabled = false;
      show('ready', 'Ready. Typing saves immediately to this fixture.');
    }
  } catch {
    halted = true;
    lock();
    show('blocked', 'Operation identity or recovery tracking is unavailable. Nothing was sent.');
  }
})();
