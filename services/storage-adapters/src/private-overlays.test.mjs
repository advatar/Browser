import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import {
  fetchPrivateOverlayNativeContent,
  privateOverlayHandlers,
  privateOverlaySummary,
  resolvePrivateOverlayHealth,
  resolvePrivateOverlayNativeRequest,
  resolvePrivateOverlaySmoke,
  samplePrivateOverlayNativeURL,
  samplePrivateOverlaySmokeURL
} from './private-overlays.mjs';

test('private overlay registry exposes managed Tor and I2P adapter ports', () => {
  assert.deepEqual(new Set(privateOverlayHandlers.map(handler => handler.id)), new Set(['tor', 'i2p']));
  assert.deepEqual(new Set(privateOverlayHandlers.map(handler => handler.port)), new Set([4893, 4894]));
  assert.equal(privateOverlaySummary().find(handler => handler.id === 'tor').adapterID, 'tor.onion');
  assert.equal(privateOverlaySummary().find(handler => handler.id === 'i2p').adapterID, 'i2p.eepproxy');
});

test('private overlay health reports reachable local proxy without claiming verification', async () => {
  const proxy = await startHTTPProxy('health-ok');
  try {
    const url = new URL('http://127.0.0.1:4894/private-overlay/i2p/health');
    url.searchParams.set('network', 'i2p');
    url.searchParams.set('adapter', 'i2p.eepproxy');
    const result = await resolvePrivateOverlayHealth('i2p', url, {
      DBROWSER_I2P_HTTP_PROXY_URL: `http://127.0.0.1:${proxy.port}`
    });

    assert.equal(result.statusCode, 200);
    assert.equal(result.payload.status, 'reachable');
    assert.equal(result.payload.verified, false);
    assert.equal(result.payload.clearnetFallback, false);
  } finally {
    await proxy.close();
  }
});

test('private overlay smoke requests reject missing fallback assertions', async () => {
  const url = samplePrivateOverlaySmokeURL('tor');
  url.searchParams.delete('no_public_gateway');

  const result = await resolvePrivateOverlaySmoke('tor', url, {
    DBROWSER_TOR_SOCKS_URL: 'socks5://127.0.0.1:9'
  });

  assert.equal(result.statusCode, 400);
  assert.equal(result.payload.status, 'misconfigured');
  assert.match(result.payload.message, /no_public_gateway=1/);
  assert.equal(result.payload.verified, false);
});

test('I2P smoke fetches fixture through local HTTP proxy without local DNS', async () => {
  const body = 'dbrowser-private-overlay-smoke-v1:i2p';
  const proxy = await startHTTPProxy(body);
  try {
    const result = await resolvePrivateOverlaySmoke('i2p', samplePrivateOverlaySmokeURL('i2p'), {
      DBROWSER_I2P_HTTP_PROXY_URL: `http://127.0.0.1:${proxy.port}`
    });

    assert.equal(result.statusCode, 200);
    assert.equal(result.payload.status, 'verified');
    assert.equal(result.payload.verified, true);
    assert.equal(result.payload.payloadSHA256, 'cded6aed04854042cbb1a1a0aa1a119f524f5b2c1052f861872584f8e7b80d4b');
    assert.equal(result.payload.dnsResolution, false);
    assert.equal(result.payload.searchFallback, false);
    assert.equal(result.payload.publicGateway, false);
    assert.equal(result.payload.clearnetFallback, false);
    assert.equal(proxy.requests[0].url, 'http://dbrowser-smoke-test.i2p/.well-known/dbrowser-private-overlay-smoke.json');
    assert.equal(proxy.requests[0].host, 'dbrowser-smoke-test.i2p');
  } finally {
    await proxy.close();
  }
});

test('Tor smoke fetches fixture through SOCKS5 domain-name connect', async () => {
  const body = 'dbrowser-private-overlay-smoke-v1:tor';
  const proxy = await startSocks5Proxy(body);
  try {
    const result = await resolvePrivateOverlaySmoke('tor', samplePrivateOverlaySmokeURL('tor'), {
      DBROWSER_TOR_SOCKS_URL: `socks5://127.0.0.1:${proxy.port}`
    });

    assert.equal(result.statusCode, 200);
    assert.equal(result.payload.status, 'verified');
    assert.equal(result.payload.verified, true);
    assert.equal(result.payload.payloadSHA256, '498fc305f7d4e17578ed598dd6db4682878ff7df911c1e6a80dbd51baa98e035');
    assert.equal(proxy.requests[0].host, 'dbrowser-smoke-test.onion');
    assert.equal(proxy.requests[0].port, 80);
    assert.match(proxy.requests[0].httpRequest, /^GET \/.well-known\/dbrowser-private-overlay-smoke\.json HTTP\/1\.1/);
  } finally {
    await proxy.close();
  }
});

test('private overlay smoke never verifies missing local runtimes', async () => {
  const result = await resolvePrivateOverlaySmoke('tor', samplePrivateOverlaySmokeURL('tor'), {
    DBROWSER_TOR_SOCKS_URL: 'socks5://127.0.0.1:9'
  });

  assert.equal(result.statusCode, 200);
  assert.equal(result.payload.status, 'not-installed');
  assert.equal(result.payload.verified, false);
  assert.equal(result.payload.clearnetFallback, false);
});

test('private overlay native route fetches content only through configured proxy', async () => {
  const body = 'dbrowser-private-overlay-smoke-v1:i2p';
  const proxy = await startHTTPProxy(body);
  try {
    const requestURL = samplePrivateOverlayNativeURL('i2p');
    requestURL.searchParams.delete('format');
    const result = resolvePrivateOverlayNativeRequest('i2p', requestURL, {
      DBROWSER_I2P_HTTP_PROXY_URL: `http://127.0.0.1:${proxy.port}`
    });

    assert.equal(result.state, 'ready');
    const fetched = await fetchPrivateOverlayNativeContent(result);
    assert.equal(fetched.statusCode, 200);
    assert.equal(fetched.body.toString('utf8'), body);
    assert.equal(proxy.requests[0].url, 'http://dbrowser-smoke-test.i2p/.well-known/dbrowser-private-overlay-smoke.json');
  } finally {
    await proxy.close();
  }
});

test('private overlay native route rejects non-overlay target hosts', () => {
  const requestURL = samplePrivateOverlayNativeURL('tor');
  requestURL.searchParams.set('uri', 'http://example.com/');

  const result = resolvePrivateOverlayNativeRequest('tor', requestURL, {
    DBROWSER_TOR_SOCKS_URL: 'socks5://127.0.0.1:9999'
  });

  assert.equal(result.statusCode, 400);
  assert.equal(result.state, 'invalid');
  assert.match(result.message, /\.onion/);
});

test('Tor SOCKS5 smoke decodes chunked HTTP bodies before digest verification', async () => {
  const body = 'dbrowser-private-overlay-smoke-v1:tor';
  const proxy = await startSocks5Proxy(body, { chunked: true });
  try {
    const result = await resolvePrivateOverlaySmoke('tor', samplePrivateOverlaySmokeURL('tor'), {
      DBROWSER_TOR_SOCKS_URL: `socks5://127.0.0.1:${proxy.port}`
    });

    assert.equal(result.statusCode, 200);
    assert.equal(result.payload.status, 'verified');
    assert.equal(result.payload.verified, true);
    assert.equal(result.payload.payloadSHA256, '498fc305f7d4e17578ed598dd6db4682878ff7df911c1e6a80dbd51baa98e035');
  } finally {
    await proxy.close();
  }
});

async function startHTTPProxy(body) {
  const requests = [];
  const server = http.createServer((req, res) => {
    requests.push({
      method: req.method,
      url: req.url,
      host: req.headers.host
    });
    res.writeHead(200, {
      'Content-Type': 'text/plain',
      'Content-Length': Buffer.byteLength(body)
    });
    res.end(body);
  });
  const port = await listen(server);
  return {
    port,
    requests,
    close: () => close(server)
  };
}

async function startSocks5Proxy(body, options = {}) {
  const requests = [];
  const server = net.createServer(socket => {
    let buffer = Buffer.alloc(0);
    let stage = 'greeting';
    socket.on('data', data => {
      buffer = Buffer.concat([buffer, data]);
      if (stage === 'greeting' && buffer.length >= 3) {
        socket.write(Buffer.from([0x05, 0x00]));
        buffer = buffer.subarray(3);
        stage = 'connect';
      }
      if (stage === 'connect' && buffer.length >= 5) {
        const hostLength = buffer[4];
        const requestLength = 5 + hostLength + 2;
        if (buffer.length < requestLength) {
          return;
        }
        const host = buffer.subarray(5, 5 + hostLength).toString('utf8');
        const port = buffer.readUInt16BE(5 + hostLength);
        requests.push({ host, port, httpRequest: '' });
        socket.write(Buffer.from([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 0]));
        buffer = buffer.subarray(requestLength);
        stage = 'http';
      }
      if (stage === 'http' && buffer.includes('\r\n\r\n')) {
        requests[requests.length - 1].httpRequest = buffer.toString('utf8');
        const response = options.chunked
          ? [
            'HTTP/1.1 200 OK',
            'Content-Type: text/plain',
            'Transfer-Encoding: chunked',
            'Connection: close',
            '',
            `${Buffer.byteLength(body).toString(16)}\r\n${body}\r\n0\r\n\r\n`
          ].join('\r\n')
          : [
            'HTTP/1.1 200 OK',
            'Content-Type: text/plain',
            `Content-Length: ${Buffer.byteLength(body)}`,
            'Connection: close',
            '',
            body
          ].join('\r\n');
        socket.end(response);
      }
    });
  });
  const port = await listen(server);
  return {
    port,
    requests,
    close: () => close(server)
  };
}

function listen(server) {
  return new Promise(resolve => {
    server.listen(0, '127.0.0.1', () => {
      resolve(server.address().port);
    });
  });
}

function close(server) {
  return new Promise(resolve => server.close(resolve));
}
