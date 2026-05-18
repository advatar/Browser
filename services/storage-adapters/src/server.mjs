import http from 'node:http';
import {
  handlerContractVersion,
  handlerSummary,
  nativeProtocolHandlers,
  resolveNativeAdapterRequest,
  sampleAdapterRequestURL
} from './handlers.mjs';

const args = new Set(process.argv.slice(2));
const hostname = process.env.DBROWSER_STORAGE_ADAPTER_HOST ?? '127.0.0.1';
const startedAt = Date.now();

if (args.has('--snapshot')) {
  console.log(`[storage-adapters] ${nativeProtocolHandlers.length} native handlers indexed`);
  process.exit(0);
}

if (args.has('--lint')) {
  const ports = new Set(nativeProtocolHandlers.map(handler => handler.port));
  const routes = new Set(nativeProtocolHandlers.map(handler => handler.routePath));
  if (ports.size !== nativeProtocolHandlers.length || routes.size !== nativeProtocolHandlers.length) {
    console.error('[storage-adapters] duplicate port or route detected');
    process.exit(1);
  }
  console.log('[storage-adapters] handler registry OK');
  process.exit(0);
}

if (args.has('--self-test')) {
  runSelfTest();
  console.log('[storage-adapters] self-test passed');
  process.exit(0);
}

const servers = nativeProtocolHandlers.map(handler => {
  const server = http.createServer((req, res) => handleRequest(req, res));
  server.listen(handler.port, hostname, () => {
    console.log(`[storage-adapters] ${handler.id} listening on http://${hostname}:${handler.port}${handler.routePath}`);
  });
  return server;
});

function handleRequest(req, res) {
  const requestURL = new URL(req.url ?? '/', `http://${req.headers.host ?? `${hostname}:4881`}`);

  if (req.method === 'GET' && requestURL.pathname === '/health') {
    return sendJson(res, 200, {
      ok: true,
      contract: handlerContractVersion,
      uptimeMs: Date.now() - startedAt,
      handlers: nativeProtocolHandlers.length,
      ports: nativeProtocolHandlers.map(handler => handler.port)
    });
  }

  if (req.method === 'GET' && requestURL.pathname === '/handlers') {
    return sendJson(res, 200, {
      ok: true,
      contract: handlerContractVersion,
      data: handlerSummary()
    });
  }

  const nativeMatch = requestURL.pathname.match(/^\/dweb\/([^/]+)\/native$/);
  if (req.method === 'GET' && nativeMatch) {
    return handleNativeAdapterRequest(nativeMatch[1], requestURL, req, res);
  }

  return sendJson(res, 404, {
    ok: false,
    error: 'not found',
    contract: handlerContractVersion
  });
}

async function handleNativeAdapterRequest(networkID, requestURL, req, res) {
  const result = resolveNativeAdapterRequest(networkID, requestURL, process.env);
  const wantsJson = requestURL.searchParams.get('format') === 'json'
    || acceptsJson(req)
    || requestURL.searchParams.get('mode') === 'describe';

  if (wantsJson) {
    return sendJson(res, result.statusCode, publicResult(result));
  }

  if (result.state !== 'ready') {
    return sendHTML(res, result.statusCode, renderRequirementPage(result));
  }

  if (process.env.DBROWSER_STORAGE_ADAPTER_REDIRECTS === '1') {
    res.writeHead(307, {
      Location: result.proxy.url,
      'Cache-Control': 'no-store'
    });
    res.end();
    return;
  }

  return proxyTarget(req, res, result);
}

async function proxyTarget(req, res, result) {
  try {
    const headers = {};
    for (const name of ['accept', 'range', 'if-none-match', 'if-modified-since']) {
      if (req.headers[name]) {
        headers[name] = req.headers[name];
      }
    }
    Object.assign(headers, result.proxy.headers);

    const upstream = await fetch(result.proxy.url, {
      method: 'GET',
      headers,
      redirect: 'follow'
    });
    const responseHeaders = {};
    for (const [name, value] of upstream.headers.entries()) {
      if (!['connection', 'transfer-encoding', 'keep-alive'].includes(name.toLowerCase())) {
        responseHeaders[name] = value;
      }
    }
    responseHeaders['X-dBrowser-Native-Adapter'] = result.adapter.id;
    responseHeaders['X-dBrowser-Native-Network'] = result.network.id;
    res.writeHead(upstream.status, responseHeaders);
    if (upstream.body) {
      const reader = upstream.body.getReader();
      while (true) {
        const { value, done } = await reader.read();
        if (done) {
          break;
        }
        res.write(Buffer.from(value));
      }
    }
    res.end();
  } catch (err) {
    sendHTML(res, 502, renderProxyFailurePage(result, err));
  }
}

function runSelfTest() {
  for (const handler of nativeProtocolHandlers) {
    const missingBackend = resolveNativeAdapterRequest(handler.id, sampleAdapterRequestURL(handler), {});
    if (missingBackend.state !== 'backend_required') {
      throw new Error(`${handler.id} should require a backend without env configuration; got ${missingBackend.state}`);
    }

    const handlerEnv = {
      [handler.handlerURLVariables[0]]: `http://127.0.0.1:9/${handler.id}/resolve`
    };
    const ready = resolveNativeAdapterRequest(handler.id, sampleAdapterRequestURL(handler), handlerEnv);
    if (ready.state !== 'ready' || !ready.target?.url?.includes(handler.id)) {
      throw new Error(`${handler.id} explicit handler did not resolve`);
    }
  }

  const sia = nativeProtocolHandlers.find(handler => handler.id === 'sia');
  const siaCredential = resolveNativeAdapterRequest(
    'sia',
    sampleAdapterRequestURL(sia),
    { SIA_RENTERD_BASE_URL: 'http://127.0.0.1:9980' }
  );
  if (siaCredential.state !== 'credential_required') {
    throw new Error(`sia should require credentials when renterd is configured; got ${siaCredential.state}`);
  }

  const invalid = sampleAdapterRequestURL('iroh');
  invalid.searchParams.set('adapter', 'wrong.adapter');
  const invalidResult = resolveNativeAdapterRequest('iroh', invalid, {});
  if (invalidResult.state !== 'invalid' || invalidResult.statusCode !== 400) {
    throw new Error('invalid adapter metadata should be rejected');
  }
}

function acceptsJson(req) {
  return String(req.headers.accept ?? '').includes('application/json');
}

function publicResult(result) {
  const copy = structuredClone(result);
  delete copy.proxy;
  return copy;
}

function sendJson(res, status, payload) {
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store'
  });
  res.end(JSON.stringify(payload, null, 2));
}

function sendHTML(res, status, html) {
  res.writeHead(status, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store'
  });
  res.end(html);
}

function renderRequirementPage(result) {
  const requirement = result.requirement ?? {};
  return renderPage(
    `${result.network?.title ?? 'Native'} handler unavailable`,
    [
      `<h1>${escapeHTML(result.network?.title ?? result.network?.id ?? 'Native')} handler unavailable</h1>`,
      `<p>${escapeHTML(result.message)}</p>`,
      '<dl>',
      `<dt>Network</dt><dd>${escapeHTML(result.network?.id ?? 'unknown')}</dd>`,
      `<dt>Adapter</dt><dd>${escapeHTML(result.adapter?.id ?? 'unknown')}</dd>`,
      `<dt>Locator</dt><dd><code>${escapeHTML(result.request?.locator ?? '')}</code></dd>`,
      `<dt>Configuration</dt><dd>${escapeHTML(requirement.configurationHint ?? 'Configure a local native handler.')}</dd>`,
      '</dl>',
      '<p>This page is generated by the local dBrowser native storage adapter service. It keeps the original decentralized URI inside the local boundary and does not fall back to a centralized resolver.</p>'
    ].join('\n')
  );
}

function renderProxyFailurePage(result, err) {
  return renderPage(
    `${result.network.title} handler proxy failed`,
    [
      `<h1>${escapeHTML(result.network.title)} handler proxy failed</h1>`,
      `<p>The native adapter resolved a local backend target, but the proxy request failed.</p>`,
      `<dl>`,
      `<dt>Adapter</dt><dd>${escapeHTML(result.adapter.id)}</dd>`,
      `<dt>Target</dt><dd><code>${escapeHTML(result.target.displayURL)}</code></dd>`,
      `<dt>Error</dt><dd>${escapeHTML(String(err.message ?? err))}</dd>`,
      `</dl>`
    ].join('\n')
  );
}

function renderPage(title, body) {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHTML(title)}</title>
  <style>
    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { max-width: 760px; margin: 48px auto; padding: 0 20px; line-height: 1.5; }
    h1 { font-size: 1.6rem; margin-bottom: 0.75rem; }
    dl { display: grid; grid-template-columns: 9rem 1fr; gap: 0.5rem 1rem; }
    dt { font-weight: 650; }
    code { overflow-wrap: anywhere; }
  </style>
</head>
<body>
${body}
</body>
</html>`;
}

function escapeHTML(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

process.on('SIGINT', () => {
  let remaining = servers.length;
  for (const server of servers) {
    server.close(() => {
      remaining -= 1;
      if (remaining === 0) {
        console.log('[storage-adapters] shutdown');
        process.exit(0);
      }
    });
  }
});
