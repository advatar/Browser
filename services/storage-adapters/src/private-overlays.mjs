import { createHash } from 'node:crypto';
import http from 'node:http';
import net from 'node:net';

export const privateOverlayContractVersion = 'dbrowser-private-overlay-adapter-v1';

const localhost = '127.0.0.1';

export const privateOverlayHandlers = [
  {
    id: 'tor',
    title: 'Tor onion service',
    port: 4893,
    routePath: '/private-overlay/tor/native',
    healthPath: '/private-overlay/tor/health',
    smokePath: '/private-overlay/tor/smoke',
    adapterID: 'tor.onion',
    proxyMode: 'socks5',
    hostnameSuffix: '.onion',
    proxyVariables: ['DBROWSER_TOR_SOCKS_URL', 'DBROWSER_ARTI_SOCKS_URL', 'TOR_SOCKS_URL'],
    defaultProxyURL: 'socks5://127.0.0.1:4898',
    fixture: {
      id: 'dbrowser-smoke-tor-v1',
      uri: 'http://dbrowser-smoke-test.onion/.well-known/dbrowser-private-overlay-smoke.json',
      expectedPayloadSHA256: '498fc305f7d4e17578ed598dd6db4682878ff7df911c1e6a80dbd51baa98e035'
    },
    requirement: 'Start the managed Tor/Arti runtime or set DBROWSER_TOR_SOCKS_URL / DBROWSER_ARTI_SOCKS_URL to a local SOCKS5 proxy.'
  },
  {
    id: 'i2p',
    title: 'I2P eepsite',
    port: 4894,
    routePath: '/private-overlay/i2p/native',
    healthPath: '/private-overlay/i2p/health',
    smokePath: '/private-overlay/i2p/smoke',
    adapterID: 'i2p.eepproxy',
    proxyMode: 'http',
    hostnameSuffix: '.i2p',
    proxyVariables: ['DBROWSER_I2P_HTTP_PROXY_URL', 'DBROWSER_I2P_HTTP_PROXY', 'I2P_HTTP_PROXY_URL'],
    defaultProxyURL: 'http://127.0.0.1:4444',
    fixture: {
      id: 'dbrowser-smoke-i2p-v1',
      uri: 'http://dbrowser-smoke-test.i2p/.well-known/dbrowser-private-overlay-smoke.json',
      expectedPayloadSHA256: 'cded6aed04854042cbb1a1a0aa1a119f524f5b2c1052f861872584f8e7b80d4b'
    },
    requirement: 'Start the managed I2P router or set DBROWSER_I2P_HTTP_PROXY_URL / DBROWSER_I2P_HTTP_PROXY to a local I2P HTTP proxy.'
  }
];

export const privateOverlayHandlersByID = new Map(privateOverlayHandlers.map(handler => [handler.id, handler]));

export function privateOverlaySummary() {
  return privateOverlayHandlers.map(handler => ({
    id: handler.id,
    title: handler.title,
    port: handler.port,
    routePath: handler.routePath,
    healthPath: handler.healthPath,
    smokePath: handler.smokePath,
    adapterID: handler.adapterID,
    proxyMode: handler.proxyMode,
    hostnameSuffix: handler.hostnameSuffix,
    proxyVariables: handler.proxyVariables,
    fixtureID: handler.fixture.id
  }));
}

export function samplePrivateOverlaySmokeURL(handlerOrID) {
  const handler = resolveHandler(handlerOrID);
  const url = new URL(`http://${localhost}:${handler.port}${handler.smokePath}`);
  url.searchParams.set('network', handler.id);
  url.searchParams.set('adapter', handler.adapterID);
  url.searchParams.set('fixture_id', handler.fixture.id);
  url.searchParams.set('uri', handler.fixture.uri);
  url.searchParams.set('expected_sha256', handler.fixture.expectedPayloadSHA256);
  url.searchParams.set('no_dns', '1');
  url.searchParams.set('no_search', '1');
  url.searchParams.set('no_public_gateway', '1');
  url.searchParams.set('no_clearnet', '1');
  return url;
}

export function samplePrivateOverlayNativeURL(handlerOrID) {
  const handler = resolveHandler(handlerOrID);
  const url = new URL(`http://${localhost}:${handler.port}${handler.routePath}`);
  url.searchParams.set('network', handler.id);
  url.searchParams.set('adapter', handler.adapterID);
  url.searchParams.set('locator_kind', handler.id === 'tor' ? '.onion hostname or onion:// URI' : '.i2p hostname or i2p:// URI');
  url.searchParams.set('uri', handler.fixture.uri);
  url.searchParams.set('privacy', 'ephemeral');
  url.searchParams.set('format', 'json');
  return url;
}

export async function resolvePrivateOverlayHealth(networkID, requestURL, env = process.env) {
  const handler = privateOverlayHandlersByID.get(networkID);
  if (!handler) {
    return privateOverlayPayload(404, {
      network: networkID,
      status: 'misconfigured',
      message: `No private-overlay handler is registered for ${networkID}.`
    });
  }

  const metadataErrors = validateBaseMetadata(handler, requestURL);
  if (metadataErrors.length > 0) {
    return privateOverlayPayload(400, {
      network: handler.id,
      status: 'misconfigured',
      message: metadataErrors.join(' ')
    });
  }

  const proxy = proxyConfig(handler, env);
  if (!proxy) {
    return privateOverlayPayload(200, {
      network: handler.id,
      status: 'not-installed',
      message: `${handler.title} proxy is not configured. ${handler.requirement}`
    });
  }

  const reachable = await probeTCP(proxy);
  if (!reachable.ok) {
    return privateOverlayPayload(200, {
      network: handler.id,
      status: 'not-installed',
      message: `${handler.title} proxy ${redactProxy(proxy)} did not respond: ${reachable.message}`
    });
  }

  return privateOverlayPayload(200, {
    network: handler.id,
    status: 'reachable',
    message: `${handler.title} local ${handler.proxyMode.toUpperCase()} proxy is reachable at ${redactProxy(proxy)}; smoke verification is pending.`,
    verified: false,
    clearnetFallback: false
  });
}

export async function resolvePrivateOverlaySmoke(networkID, requestURL, env = process.env) {
  const handler = privateOverlayHandlersByID.get(networkID);
  if (!handler) {
    return smokePayload(404, {
      network: networkID,
      status: 'misconfigured',
      message: `No private-overlay handler is registered for ${networkID}.`
    });
  }

  const metadataErrors = validateSmokeMetadata(handler, requestURL);
  if (metadataErrors.length > 0) {
    return smokePayload(400, {
      network: handler.id,
      fixtureID: handler.fixture.id,
      status: 'misconfigured',
      message: metadataErrors.join(' ')
    });
  }

  const proxy = proxyConfig(handler, env);
  if (!proxy) {
    return smokePayload(200, {
      network: handler.id,
      fixtureID: handler.fixture.id,
      status: 'not-installed',
      message: `${handler.title} proxy is not configured. ${handler.requirement}`
    });
  }

  try {
    const fetched = await fetchThroughOverlayProxy(handler, handler.fixture.uri, proxy);
    const digest = sha256Hex(fetched.body);
    const verified = digest === handler.fixture.expectedPayloadSHA256;
    return smokePayload(200, {
      network: handler.id,
      fixtureID: handler.fixture.id,
      status: verified ? 'verified' : 'misconfigured',
      message: verified
        ? `${handler.title} smoke fixture fetched through ${handler.proxyMode.toUpperCase()} proxy without DNS, search, public gateway, or clearnet fallback.`
        : `${handler.title} smoke fixture digest ${digest} did not match expected digest.`,
      verified,
      payloadSHA256: digest,
      clearnetFallback: false,
      dnsResolution: false,
      searchFallback: false,
      publicGateway: false
    });
  } catch (err) {
    return smokePayload(200, {
      network: handler.id,
      fixtureID: handler.fixture.id,
      status: 'not-installed',
      message: `${handler.title} smoke fixture could not be fetched through ${redactProxy(proxy)}: ${err.message ?? err}`
    });
  }
}

export function resolvePrivateOverlayNativeRequest(networkID, requestURL, env = process.env) {
  const handler = privateOverlayHandlersByID.get(networkID);
  if (!handler) {
    return {
      ok: false,
      state: 'invalid',
      statusCode: 404,
      message: `No private-overlay handler is registered for ${networkID}.`,
      contract: privateOverlayContractVersion,
      network: { id: networkID }
    };
  }

  const metadataErrors = validateNativeMetadata(handler, requestURL);
  if (metadataErrors.length > 0) {
    return privateOverlayNativeResult(handler, requestURL, {
      ok: false,
      state: 'invalid',
      statusCode: 400,
      message: metadataErrors.join(' ')
    });
  }

  const proxy = proxyConfig(handler, env);
  if (!proxy) {
    return privateOverlayNativeResult(handler, requestURL, {
      ok: false,
      state: 'runtime_required',
      statusCode: 424,
      message: `${handler.title} proxy is not configured. ${handler.requirement}`
    });
  }

  return privateOverlayNativeResult(handler, requestURL, {
    ok: true,
    state: 'ready',
    statusCode: 200,
    message: `${handler.title} private-overlay adapter is ready through ${handler.proxyMode.toUpperCase()} proxy ${redactProxy(proxy)}.`,
    proxy
  });
}

export async function fetchPrivateOverlayNativeContent(result) {
  if (result.state !== 'ready') {
    throw new Error(`Private-overlay adapter is not ready: ${result.message}`);
  }
  const fetched = await fetchThroughOverlayProxy(result.handler, result.request.uri, result.proxy);
  return {
    statusCode: fetched.statusCode,
    contentType: fetched.contentType,
    body: fetched.body
  };
}

export async function fetchThroughOverlayProxy(handler, uri, proxy) {
  const target = new URL(uri);
  const targetErrors = validateOverlayTargetURI(handler, uri);
  if (targetErrors.length > 0) {
    throw new Error(targetErrors.join(' '));
  }
  if (handler.proxyMode === 'socks5') {
    return fetchHTTPViaSocks5(target, proxy);
  }
  if (handler.proxyMode === 'http') {
    return fetchHTTPViaHTTPProxy(target, proxy);
  }
  throw new Error(`Unsupported private-overlay proxy mode ${handler.proxyMode}.`);
}

function resolveHandler(handlerOrID) {
  const handler = typeof handlerOrID === 'string' ? privateOverlayHandlersByID.get(handlerOrID) : handlerOrID;
  if (!handler) {
    throw new Error(`unknown private-overlay handler ${handlerOrID}`);
  }
  return handler;
}

function validateBaseMetadata(handler, requestURL) {
  const query = requestURL.searchParams;
  const errors = [];
  if ((query.get('network') ?? handler.id) !== handler.id) {
    errors.push(`Network mismatch: expected ${handler.id}.`);
  }
  if ((query.get('adapter') ?? handler.adapterID) !== handler.adapterID) {
    errors.push(`Adapter mismatch: expected ${handler.adapterID}.`);
  }
  return errors;
}

function validateSmokeMetadata(handler, requestURL) {
  const query = requestURL.searchParams;
  const errors = validateBaseMetadata(handler, requestURL);
  if (query.get('fixture_id') !== handler.fixture.id) {
    errors.push(`Fixture mismatch: expected ${handler.fixture.id}.`);
  }
  if (query.get('uri') !== handler.fixture.uri) {
    errors.push('Smoke fixture URI mismatch.');
  }
  if ((query.get('expected_sha256') ?? '').toLowerCase() !== handler.fixture.expectedPayloadSHA256) {
    errors.push('Smoke fixture digest mismatch.');
  }
  for (const flag of ['no_dns', 'no_search', 'no_public_gateway', 'no_clearnet']) {
    if (!truthy(query.get(flag))) {
      errors.push(`Smoke request must set ${flag}=1.`);
    }
  }
  return errors;
}

function validateNativeMetadata(handler, requestURL) {
  const query = requestURL.searchParams;
  const errors = validateBaseMetadata(handler, requestURL);
  if (!query.get('uri')) {
    errors.push('Private-overlay URI is required.');
  } else {
    errors.push(...validateOverlayTargetURI(handler, query.get('uri')));
  }
  if ((query.get('privacy') ?? 'ephemeral') !== 'ephemeral') {
    errors.push('Private-overlay requests must keep privacy=ephemeral.');
  }
  return errors;
}

function validateOverlayTargetURI(handler, uri) {
  const errors = [];
  let target;
  try {
    target = new URL(uri);
  } catch {
    return ['Private-overlay URI must be an absolute HTTP URL.'];
  }

  if (target.protocol !== 'http:') {
    errors.push('Only HTTP private-overlay smoke/native fetches are supported by the local adapter harness.');
  }

  if (!target.hostname.toLowerCase().endsWith(handler.hostnameSuffix)) {
    errors.push(`Private-overlay URI host must end with ${handler.hostnameSuffix}.`);
  }

  return errors;
}

function privateOverlayNativeResult(handler, requestURL, fields) {
  return {
    ok: fields.ok,
    state: fields.state,
    statusCode: fields.statusCode,
    message: fields.message,
    contract: privateOverlayContractVersion,
    network: {
      id: handler.id,
      title: handler.title
    },
    adapter: {
      id: handler.adapterID,
      routePath: handler.routePath,
      port: handler.port,
      proxyMode: handler.proxyMode,
      hostnameSuffix: handler.hostnameSuffix
    },
    request: {
      uri: requestURL.searchParams.get('uri') ?? '',
      privacy: requestURL.searchParams.get('privacy') ?? 'ephemeral',
      locatorKind: requestURL.searchParams.get('locator_kind') ?? ''
    },
    runtime: {
      requirement: handler.requirement,
      proxyVariables: handler.proxyVariables,
      defaultProxyURL: handler.defaultProxyURL
    },
    handler,
    proxy: fields.proxy ?? null
  };
}

function proxyConfig(handler, env) {
  for (const variable of handler.proxyVariables) {
    const value = trim(env[variable]);
    if (value) {
      return normalizeProxyURL(value, handler.proxyMode);
    }
  }
  return normalizeProxyURL(handler.defaultProxyURL, handler.proxyMode);
}

function normalizeProxyURL(value, mode) {
  const trimmed = trim(value);
  if (!trimmed) {
    return null;
  }
  const withScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(trimmed)
    ? trimmed
    : `${mode === 'socks5' ? 'socks5' : 'http'}://${trimmed}`;
  const url = new URL(withScheme);
  return {
    mode,
    hostname: url.hostname || localhost,
    port: Number(url.port || (mode === 'socks5' ? 9050 : 4444)),
    url: `${url.protocol}//${url.host}`
  };
}

function redactProxy(proxy) {
  return `${proxy.mode}://${proxy.hostname}:${proxy.port}`;
}

async function probeTCP(proxy) {
  return new Promise(resolve => {
    const socket = net.connect({ host: proxy.hostname, port: proxy.port });
    const timer = setTimeout(() => {
      socket.destroy();
      resolve({ ok: false, message: 'timeout' });
    }, 350);
    socket.once('connect', () => {
      clearTimeout(timer);
      socket.end();
      resolve({ ok: true });
    });
    socket.once('error', err => {
      clearTimeout(timer);
      resolve({ ok: false, message: err.code ?? err.message });
    });
  });
}

async function fetchHTTPViaHTTPProxy(target, proxy) {
  return new Promise((resolve, reject) => {
    const req = http.request({
      host: proxy.hostname,
      port: proxy.port,
      method: 'GET',
      path: target.toString(),
      headers: {
        Accept: 'application/octet-stream',
        Host: target.host,
        Connection: 'close'
      },
      timeout: 2_000
    }, res => {
      const chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('end', () => {
        const body = Buffer.concat(chunks);
        if ((res.statusCode ?? 0) < 200 || (res.statusCode ?? 0) >= 300) {
          reject(new Error(`proxy returned HTTP ${res.statusCode}`));
          return;
        }
        resolve({
          statusCode: res.statusCode ?? 200,
          contentType: res.headers['content-type'] ?? 'application/octet-stream',
          body
        });
      });
    });
    req.on('timeout', () => {
      req.destroy(new Error('proxy request timeout'));
    });
    req.on('error', reject);
    req.end();
  });
}

async function fetchHTTPViaSocks5(target, proxy) {
  return new Promise((resolve, reject) => {
    const socket = net.connect({ host: proxy.hostname, port: proxy.port });
    let buffer = Buffer.alloc(0);
    let stage = 'greeting';
    const chunks = [];
    const timeout = setTimeout(() => {
      socket.destroy();
      reject(new Error('SOCKS5 request timeout'));
    }, 2_000);

    socket.once('connect', () => {
      socket.write(Buffer.from([0x05, 0x01, 0x00]));
    });

    socket.on('data', data => {
      buffer = Buffer.concat([buffer, data]);
      try {
        if (stage === 'greeting' && buffer.length >= 2) {
          if (buffer[0] !== 0x05 || buffer[1] !== 0x00) {
            throw new Error('SOCKS5 proxy rejected no-auth handshake');
          }
          buffer = buffer.subarray(2);
          stage = 'connect';
          socket.write(socks5ConnectRequest(target.hostname, Number(target.port || 80)));
        }

        if (stage === 'connect' && buffer.length >= 5) {
          const addressLength = socks5ResponseLength(buffer);
          if (addressLength === null || buffer.length < addressLength) {
            return;
          }
          if (buffer[1] !== 0x00) {
            throw new Error(`SOCKS5 connect failed with code ${buffer[1]}`);
          }
          buffer = buffer.subarray(addressLength);
          stage = 'http';
          const path = `${target.pathname || '/'}${target.search || ''}`;
          socket.write([
            `GET ${path} HTTP/1.1`,
            `Host: ${target.host}`,
            'Accept: application/octet-stream',
            'Connection: close',
            '',
            ''
          ].join('\r\n'));
        }

        if (stage === 'http') {
          chunks.push(buffer);
          buffer = Buffer.alloc(0);
        }
      } catch (err) {
        clearTimeout(timeout);
        socket.destroy();
        reject(err);
      }
    });

    socket.on('end', () => {
      clearTimeout(timeout);
      try {
        resolve(parseHTTPResponse(Buffer.concat(chunks)));
      } catch (err) {
        reject(err);
      }
    });
    socket.on('error', err => {
      clearTimeout(timeout);
      reject(err);
    });
  });
}

function socks5ConnectRequest(hostname, port) {
  const host = Buffer.from(hostname, 'utf8');
  if (host.length > 255) {
    throw new Error('SOCKS5 hostname is too long');
  }
  return Buffer.concat([
    Buffer.from([0x05, 0x01, 0x00, 0x03, host.length]),
    host,
    Buffer.from([(port >> 8) & 0xff, port & 0xff])
  ]);
}

function socks5ResponseLength(buffer) {
  const atyp = buffer[3];
  if (atyp === 0x01) {
    return 10;
  }
  if (atyp === 0x03 && buffer.length >= 5) {
    return 5 + buffer[4] + 2;
  }
  if (atyp === 0x04) {
    return 22;
  }
  return null;
}

function parseHTTPResponse(raw) {
  const separator = raw.indexOf('\r\n\r\n');
  if (separator < 0) {
    throw new Error('upstream response did not contain HTTP headers');
  }
  const headerText = raw.subarray(0, separator).toString('utf8');
  const body = raw.subarray(separator + 4);
  const [statusLine, ...headerLines] = headerText.split('\r\n');
  const statusCode = Number(statusLine.split(/\s+/)[1]);
  if (statusCode < 200 || statusCode >= 300) {
    throw new Error(`upstream returned HTTP ${statusCode}`);
  }
  const headers = Object.fromEntries(headerLines.map(line => {
    const index = line.indexOf(':');
    if (index < 0) {
      return [line.toLowerCase(), ''];
    }
    return [line.slice(0, index).toLowerCase(), line.slice(index + 1).trim()];
  }));
  const decodedBody = isChunked(headers) ? decodeChunkedBody(body) : body;
  return {
    statusCode,
    contentType: headers['content-type'] ?? 'application/octet-stream',
    body: decodedBody
  };
}

function isChunked(headers) {
  return String(headers['transfer-encoding'] ?? '')
    .toLowerCase()
    .split(',')
    .map(part => part.trim())
    .includes('chunked');
}

function decodeChunkedBody(body) {
  const chunks = [];
  let offset = 0;

  while (offset < body.length) {
    const lineEnd = body.indexOf('\r\n', offset);
    if (lineEnd < 0) {
      throw new Error('chunked response ended before chunk size');
    }

    const sizeText = body.subarray(offset, lineEnd).toString('ascii').split(';')[0].trim();
    const size = Number.parseInt(sizeText, 16);
    if (!Number.isFinite(size)) {
      throw new Error(`invalid chunk size ${sizeText}`);
    }

    const chunkStart = lineEnd + 2;
    const chunkEnd = chunkStart + size;
    if (chunkEnd + 2 > body.length) {
      throw new Error('chunked response ended before chunk data');
    }

    if (size === 0) {
      return Buffer.concat(chunks);
    }

    chunks.push(body.subarray(chunkStart, chunkEnd));
    if (body.subarray(chunkEnd, chunkEnd + 2).toString('ascii') !== '\r\n') {
      throw new Error('chunked response chunk missing terminator');
    }
    offset = chunkEnd + 2;
  }

  throw new Error('chunked response ended before final chunk');
}

function privateOverlayPayload(statusCode, payload) {
  return {
    statusCode,
    payload: {
      ok: statusCode >= 200 && statusCode < 300 && !['misconfigured', 'blocked', 'not-installed'].includes(payload.status),
      contract: privateOverlayContractVersion,
      network: payload.network,
      status: payload.status,
      message: payload.message,
      verified: payload.verified ?? false,
      clearnetFallback: payload.clearnetFallback ?? false
    }
  };
}

function smokePayload(statusCode, payload) {
  return {
    statusCode,
    payload: {
      ok: payload.verified === true,
      contract: privateOverlayContractVersion,
      network: payload.network,
      fixtureID: payload.fixtureID,
      status: payload.status,
      message: payload.message,
      verified: payload.verified ?? false,
      payloadSHA256: payload.payloadSHA256,
      clearnetFallback: payload.clearnetFallback ?? false,
      dnsResolution: payload.dnsResolution ?? false,
      searchFallback: payload.searchFallback ?? false,
      publicGateway: payload.publicGateway ?? false
    }
  };
}

function sha256Hex(value) {
  return createHash('sha256').update(value).digest('hex');
}

function truthy(value) {
  return value === '1' || value === 'true';
}

function trim(value) {
  return String(value ?? '').trim();
}
