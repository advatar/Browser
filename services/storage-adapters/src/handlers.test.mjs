import test from 'node:test';
import assert from 'node:assert/strict';
import {
  nativeAdapterStage,
  nativeProtocolHandlers,
  resolveNativeAdapterRequest,
  sampleAdapterRequestURL,
  sampleURIForScheme
} from './handlers.mjs';

const expectedNetworkIDs = new Set([
  'filecoin',
  'walrus',
  'iroh',
  'hypercore',
  'sia',
  'storj',
  'tahoe-lafs',
  'autonomi',
  'bittorrent',
  'ceramic',
  'orbitdb',
  'radicle'
]);

test('native handler registry covers every Swift storage adapter protocol', () => {
  assert.deepEqual(new Set(nativeProtocolHandlers.map(handler => handler.id)), expectedNetworkIDs);

  const ports = new Set();
  for (const handler of nativeProtocolHandlers) {
    assert.equal(handler.routePath, `/dweb/${handler.id}/native`);
    assert.equal(handler.port >= 4881 && handler.port <= 4892, true);
    assert.equal(handler.handlerID.length > 0, true);
    assert.equal(handler.issueNumber >= 119 && handler.issueNumber <= 130, true);
    assert.equal(handler.verificationRequirements.length >= 2, true);
    ports.add(handler.port);
  }

  assert.equal(ports.size, nativeProtocolHandlers.length);
});

test('handlers require a local backend when no native daemon is configured', () => {
  for (const handler of nativeProtocolHandlers) {
    for (const scheme of handler.schemes) {
      const requestURL = sampleAdapterRequestURL(handler, scheme);
      const result = resolveNativeAdapterRequest(handler.id, requestURL, {});

      assert.equal(result.state, 'backend_required', `${handler.id}/${scheme}`);
      assert.equal(result.statusCode, 424);
      assert.equal(result.network.id, handler.id);
      assert.equal(result.adapter.stage, nativeAdapterStage);
      assert.equal(result.request.scheme, scheme);
      assert.equal(result.request.originalURIDigest.startsWith('0x'), true);
      assert.deepEqual(result.requirement.handlerURLVariables, handler.handlerURLVariables);
    }
  }
});

test('explicit per-protocol handler URLs make every handler ready', () => {
  for (const handler of nativeProtocolHandlers) {
    const requestURL = sampleAdapterRequestURL(handler);
    const env = {
      [handler.handlerURLVariables[0]]: `http://127.0.0.1:9/${handler.id}/resolve`
    };
    const result = resolveNativeAdapterRequest(handler.id, requestURL, env);

    assert.equal(result.state, 'ready', handler.id);
    assert.equal(result.statusCode, 200);
    assert.equal(result.target.source, handler.handlerURLVariables[0]);
    assert.equal(result.target.proxyMode, 'configured-handler');
    assert.equal(result.proxy.url.includes(`network=${handler.id}`), true);
    assert.equal(result.proxy.url.includes(`resolution_stage=${nativeAdapterStage}`), true);
    assert.equal(result.proxy.url.includes('uri='), true);
  }
});

test('known local backend variables produce protocol-specific target URLs', () => {
  const filecoin = resolveNativeAdapterRequest(
    'filecoin',
    sampleAdapterRequestURL('filecoin', 'piececid'),
    { FILECOIN_RETRIEVAL_BASE_URL: 'http://127.0.0.1:7777/retrieval' }
  );
  assert.equal(filecoin.state, 'ready');
  assert.equal(filecoin.target.source, 'FILECOIN_RETRIEVAL_BASE_URL');
  assert.equal(filecoin.proxy.url.startsWith('http://127.0.0.1:7777/retrieval/'), true);

  const walrus = resolveNativeAdapterRequest(
    'walrus',
    sampleAdapterRequestURL('walrus'),
    { WALRUS_SITES_BASE_URL: 'http://127.0.0.1:7778/sites' }
  );
  assert.equal(walrus.state, 'ready');
  assert.equal(walrus.target.source, 'WALRUS_SITES_BASE_URL');
  assert.equal(walrus.proxy.url.includes('/sites/abc123xyz/site/index.html'), true);

  const iroh = resolveNativeAdapterRequest(
    'iroh',
    sampleAdapterRequestURL('iroh'),
    { IROH_BLOBS_GATEWAY_URL: 'http://127.0.0.1:7779' }
  );
  assert.equal(iroh.state, 'ready');
  assert.equal(iroh.proxy.url.includes('/blobs/blake3examplehash/app.json'), true);
});

test('credential-scoped handlers redact secrets and require credentials where needed', () => {
  const tahoe = resolveNativeAdapterRequest(
    'tahoe-lafs',
    sampleAdapterRequestURL('tahoe-lafs', 'tahoe'),
    { TAHOE_LAFS_GATEWAY_URL: 'http://127.0.0.1:3456' }
  );
  assert.equal(tahoe.state, 'ready');
  assert.equal(tahoe.request.locator, '<redacted>');
  assert.equal(tahoe.request.originalURI, 'tahoe://<redacted-capability>');
  assert.equal(tahoe.target.displayURL, 'http://127.0.0.1:3456/%3Credacted-capability%3E');

  const siaMissingCredential = resolveNativeAdapterRequest(
    'sia',
    sampleAdapterRequestURL('sia'),
    { SIA_RENTERD_BASE_URL: 'http://127.0.0.1:9980' }
  );
  assert.equal(siaMissingCredential.state, 'credential_required');
  assert.equal(siaMissingCredential.statusCode, 401);

  const siaWithCredential = resolveNativeAdapterRequest(
    'sia',
    sampleAdapterRequestURL('sia'),
    {
      SIA_RENTERD_BASE_URL: 'http://127.0.0.1:9980',
      SIA_RENTERD_API_TOKEN: 'local-token'
    }
  );
  assert.equal(siaWithCredential.state, 'ready');
  assert.deepEqual(siaWithCredential.proxy.headers, { Authorization: 'Bearer local-token' });
});

test('handlers reject altered Swift adapter metadata', () => {
  const badNetwork = sampleAdapterRequestURL('filecoin');
  badNetwork.searchParams.set('network', 'iroh');
  assert.equal(resolveNativeAdapterRequest('filecoin', badNetwork, {}).state, 'invalid');

  const badAdapter = sampleAdapterRequestURL('iroh');
  badAdapter.searchParams.set('adapter', 'iroh.fake');
  assert.equal(resolveNativeAdapterRequest('iroh', badAdapter, {}).state, 'invalid');

  const badStage = sampleAdapterRequestURL('radicle');
  badStage.searchParams.set('resolution_stage', 'remote-runtime-handoff');
  assert.equal(resolveNativeAdapterRequest('radicle', badStage, {}).state, 'invalid');
});

test('torrent handler accepts btih magnets and rejects missing infohashes', () => {
  const magnet = sampleAdapterRequestURL('bittorrent', 'magnet');
  magnet.searchParams.set('uri', `${sampleURIForScheme('magnet')}&ws=https%3A%2F%2Fexample.com%2Fbundle.car`);
  const seeded = resolveNativeAdapterRequest('bittorrent', magnet, {});
  assert.equal(seeded.state, 'ready');
  assert.equal(seeded.target.source, 'magnet-web-seed');

  const invalid = sampleAdapterRequestURL('bittorrent', 'magnet');
  invalid.searchParams.set('uri', 'magnet:?dn=no-infohash');
  invalid.searchParams.set('locator', 'magnet:?dn=no-infohash');
  const result = resolveNativeAdapterRequest('bittorrent', invalid, {});
  assert.equal(result.state, 'invalid');
});
