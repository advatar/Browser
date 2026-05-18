import { URL } from 'node:url';

export const handlerContractVersion = 'dweb-native-adapter-v1';
export const nativeAdapterStage = 'native-local-adapter';

const localhost = '127.0.0.1';

export const nativeProtocolHandlers = [
  {
    id: 'filecoin',
    title: 'Filecoin',
    port: 4881,
    routePath: '/dweb/filecoin/native',
    schemes: ['filecoin', 'piececid', 'fil'],
    handlerID: 'filecoin.piece-car',
    issueNumber: 119,
    locatorKind: 'Filecoin CID, piece CID, or storage deal reference',
    handlerURLVariables: ['DBROWSER_FILECOIN_HANDLER_URL'],
    backendVariables: ['FILECOIN_RETRIEVAL_BASE_URL'],
    credentialVariables: [],
    trustBoundary: 'Local Filecoin retrieval service supplies CAR or payload bytes; the browser keeps CID, deal, and piece verification metadata visible.',
    verificationRequirements: [
      'Preserve payload CID, piece CID, path, query, and fragment.',
      'Verify CAR block roots and piece inclusion before treating retrieved content as trusted.'
    ],
    requirement: {
      name: 'Filecoin retrieval client',
      reason: 'Piece CIDs, deal references, and provider locators require Filecoin retrieval plus CAR/piece verification.',
      configurationHint: 'Set DBROWSER_FILECOIN_HANDLER_URL or FILECOIN_RETRIEVAL_BASE_URL to a local Lassie/Boost/Filecoin retrieval bridge.'
    },
    validate: validateNonEmptyLocator,
    buildTarget: buildFilecoinTarget
  },
  {
    id: 'walrus',
    title: 'Walrus',
    port: 4882,
    routePath: '/dweb/walrus/native',
    schemes: ['walrus'],
    handlerID: 'walrus.blob',
    issueNumber: 120,
    locatorKind: 'Walrus blob ID, site path, or quilt member',
    handlerURLVariables: ['DBROWSER_WALRUS_HANDLER_URL'],
    backendVariables: ['WALRUS_SITES_BASE_URL', 'WALRUS_AGGREGATOR_BASE_URL'],
    credentialVariables: [],
    trustBoundary: 'Local Walrus handler resolves site, quilt, and blob metadata while the browser preserves blob IDs and Sui/Walrus verification inputs.',
    verificationRequirements: [
      'Preserve blob ID and any epoch or object metadata.',
      'Validate blob digest and Sui/Walrus metadata before install or render.'
    ],
    requirement: {
      name: 'Walrus Sites, quilt, or aggregator handler',
      reason: 'Path-bearing Walrus locators require a Sites/quilt-aware bridge; single-blob aggregator paths can be handled when an aggregator is configured.',
      configurationHint: 'Set DBROWSER_WALRUS_HANDLER_URL, WALRUS_SITES_BASE_URL, or WALRUS_AGGREGATOR_BASE_URL.'
    },
    validate: validateNonEmptyLocator,
    buildTarget: buildWalrusTarget
  },
  {
    id: 'iroh',
    title: 'Iroh blobs',
    port: 4883,
    routePath: '/dweb/iroh/native',
    schemes: ['iroh', 'iroh-blob'],
    handlerID: 'iroh.blake3-blob',
    issueNumber: 121,
    locatorKind: 'Iroh blob hash or ticket',
    handlerURLVariables: ['DBROWSER_IROH_HANDLER_URL'],
    backendVariables: ['IROH_BLOBS_GATEWAY_URL'],
    credentialVariables: [],
    trustBoundary: 'Local Iroh runtime handles peer dialing and streaming while the browser preserves BLAKE3 hash or ticket verification metadata.',
    verificationRequirements: [
      'Preserve blob hash, ticket, peer hints, and path.',
      'Verify BLAKE3 content hash before exposing fetched bytes.'
    ],
    requirement: {
      name: 'Iroh endpoint and iroh-blobs store',
      reason: 'Iroh tickets need peer dialing and verified BLAKE3 streaming.',
      configurationHint: 'Set DBROWSER_IROH_HANDLER_URL or IROH_BLOBS_GATEWAY_URL to a local Iroh bridge.'
    },
    validate: validateNonEmptyLocator,
    buildTarget: buildPathTarget('IROH_BLOBS_GATEWAY_URL', '/blobs')
  },
  {
    id: 'hypercore',
    title: 'Hypercore / Hyperdrive',
    port: 4884,
    routePath: '/dweb/hypercore/native',
    schemes: ['hyper', 'hypercore', 'hyperdrive', 'pear', 'dat'],
    handlerID: 'hypercore.feed',
    issueNumber: 122,
    locatorKind: 'Hypercore public key, Hyperdrive key, or Pear app key',
    handlerURLVariables: ['DBROWSER_HYPERCORE_HANDLER_URL'],
    backendVariables: ['HYPERDRIVE_GATEWAY_URL', 'HYPERCORE_GATEWAY_URL'],
    credentialVariables: [],
    trustBoundary: 'Local Hypercore runtime handles discovery and replication while the browser preserves signed feed, version, and path metadata.',
    verificationRequirements: [
      'Preserve feed key, drive path, version, and discovery key hints.',
      'Verify signed tree or feed blocks before trusting mutable catalog state.'
    ],
    requirement: {
      name: 'Hypercore or Hyperdrive runtime',
      reason: 'Hypercore-family URIs require discovery, replication, and signed feed/Merkle tree verification.',
      configurationHint: 'Set DBROWSER_HYPERCORE_HANDLER_URL, HYPERDRIVE_GATEWAY_URL, or HYPERCORE_GATEWAY_URL.'
    },
    validate: validateNonEmptyLocator,
    buildTarget: buildFirstPathTarget(['HYPERDRIVE_GATEWAY_URL', 'HYPERCORE_GATEWAY_URL'], '/')
  },
  {
    id: 'sia',
    title: 'Sia',
    port: 4885,
    routePath: '/dweb/sia/native',
    schemes: ['sia'],
    handlerID: 'sia.renterd-object',
    issueNumber: 123,
    locatorKind: 'Sia object ID, Skylink, or renterd path',
    handlerURLVariables: ['DBROWSER_SIA_HANDLER_URL'],
    backendVariables: ['SIA_RENTERD_BASE_URL'],
    credentialVariables: ['SIA_RENTERD_AUTH_HEADER', 'SIA_RENTERD_API_TOKEN', 'SIA_RENTERD_API_PASSWORD'],
    credentialScoped: true,
    trustBoundary: 'Local renterd bridge owns host retrieval and credentials while the browser keeps object path, checksum, and encryption metadata separate.',
    verificationRequirements: [
      'Preserve object path, bucket, skylink, and encryption metadata.',
      'Validate object checksum and decrypt locally when keys are user-held.'
    ],
    requirement: {
      name: 'Sia renterd or host retrieval gateway',
      reason: 'Sia object paths and Skylinks require renter credentials, host retrieval, or object metadata before bytes can be fetched.',
      configurationHint: 'Set DBROWSER_SIA_HANDLER_URL or SIA_RENTERD_BASE_URL plus an auth header/token environment variable.'
    },
    validate: validateNonEmptyLocator,
    buildTarget: buildSiaTarget
  },
  {
    id: 'storj',
    title: 'Storj',
    port: 4886,
    routePath: '/dweb/storj/native',
    schemes: ['storj'],
    handlerID: 'storj.uplink-object',
    issueNumber: 124,
    locatorKind: 'Storj bucket and object path',
    handlerURLVariables: ['DBROWSER_STORJ_HANDLER_URL'],
    backendVariables: ['STORJ_LINKSHARING_BASE_URL'],
    credentialVariables: ['STORJ_ACCESS_GRANT'],
    credentialScoped: true,
    trustBoundary: 'Local Storj handler owns grants and passphrases while the browser preserves bucket, object, version, and credential-scope metadata.',
    verificationRequirements: [
      'Preserve bucket, object key, grant scope, version, and path.',
      'Validate object checksum and avoid leaking encryption grants to generic page context.'
    ],
    requirement: {
      name: 'Storj uplink, access grant, or linksharing handler',
      reason: 'Storj bucket/object URIs are encrypted and scoped by grants; the browser must not invent or expose credentials.',
      configurationHint: 'Set DBROWSER_STORJ_HANDLER_URL or STORJ_LINKSHARING_BASE_URL. Keep STORJ_ACCESS_GRANT inside the handler boundary.'
    },
    validate: validateNonEmptyLocator,
    buildTarget: buildPathTarget('STORJ_LINKSHARING_BASE_URL', '/')
  },
  {
    id: 'tahoe-lafs',
    title: 'Tahoe-LAFS',
    port: 4887,
    routePath: '/dweb/tahoe-lafs/native',
    schemes: ['tahoe', 'lafs'],
    handlerID: 'tahoe.capability',
    issueNumber: 125,
    locatorKind: 'Tahoe-LAFS capability URI',
    handlerURLVariables: ['DBROWSER_TAHOE_LAFS_HANDLER_URL', 'DBROWSER_TAHOE_HANDLER_URL'],
    backendVariables: ['TAHOE_LAFS_GATEWAY_URL'],
    credentialVariables: [],
    credentialScoped: true,
    secretLocator: true,
    trustBoundary: 'Local Tahoe handler dereferences capabilities inside the user-selected grid boundary while the browser treats capabilities as secrets.',
    verificationRequirements: [
      'Preserve read/write capability type without promoting it into visible page text.',
      'Verify immutable directory or file hashes when capabilities include them.'
    ],
    requirement: {
      name: 'Tahoe-LAFS gateway',
      reason: 'Tahoe capabilities are least-authority secrets and must be dereferenced through a user-selected grid gateway.',
      configurationHint: 'Set DBROWSER_TAHOE_LAFS_HANDLER_URL or TAHOE_LAFS_GATEWAY_URL.'
    },
    validate: validateNonEmptyLocator,
    buildTarget: buildPathTarget('TAHOE_LAFS_GATEWAY_URL', '/uri')
  },
  {
    id: 'autonomi',
    title: 'Autonomi',
    port: 4888,
    routePath: '/dweb/autonomi/native',
    schemes: ['autonomi', 'safe'],
    handlerID: 'autonomi.address',
    issueNumber: 126,
    locatorKind: 'Autonomi address or SAFE URL',
    handlerURLVariables: ['DBROWSER_AUTONOMI_HANDLER_URL'],
    backendVariables: ['AUTONOMI_CLIENT_GATEWAY_URL'],
    credentialVariables: ['AUTONOMI_SECRET_KEY', 'AUTONOMI_WALLET_KEY'],
    credentialScoped: true,
    trustBoundary: 'Local Autonomi client resolves data maps and private chunks while the browser preserves content-address and decryption metadata.',
    verificationRequirements: [
      'Preserve address, data map, and private access metadata.',
      'Verify encrypted chunk map and content address before install or render.'
    ],
    requirement: {
      name: 'Autonomi client',
      reason: 'Autonomi data maps and private access metadata require the Autonomi network client and local decryption path.',
      configurationHint: 'Set DBROWSER_AUTONOMI_HANDLER_URL or AUTONOMI_CLIENT_GATEWAY_URL.'
    },
    validate: validateNonEmptyLocator,
    buildTarget: buildPathTarget('AUTONOMI_CLIENT_GATEWAY_URL', '/')
  },
  {
    id: 'bittorrent',
    title: 'BitTorrent / WebTorrent',
    port: 4889,
    routePath: '/dweb/bittorrent/native',
    schemes: ['magnet', 'bittorrent', 'webtorrent'],
    handlerID: 'bittorrent.infohash',
    issueNumber: 127,
    locatorKind: 'BTIH/BTMH infohash or torrent URI',
    handlerURLVariables: ['DBROWSER_BITTORRENT_HANDLER_URL'],
    backendVariables: ['BITTORRENT_ENGINE_URL', 'WEBTORRENT_ENGINE_URL'],
    credentialVariables: [],
    trustBoundary: 'Local torrent engine owns tracker, DHT, or WebRTC peer discovery while the browser preserves infohash and signed manifest metadata.',
    verificationRequirements: [
      'Preserve xt, dn, tr, ws, and exact magnet parameters.',
      'Verify infohash and signed release manifest before trusting downloaded app content.'
    ],
    requirement: {
      name: 'BitTorrent or WebTorrent engine',
      reason: 'Magnet links without HTTP web seeds need tracker, DHT, or WebRTC peer discovery plus infohash verification.',
      configurationHint: 'Set DBROWSER_BITTORRENT_HANDLER_URL, BITTORRENT_ENGINE_URL, or WEBTORRENT_ENGINE_URL.'
    },
    validate: validateTorrentLocator,
    buildTarget: buildBitTorrentTarget
  },
  {
    id: 'ceramic',
    title: 'Ceramic',
    port: 4890,
    routePath: '/dweb/ceramic/native',
    schemes: ['ceramic', 'ceramic-stream'],
    handlerID: 'ceramic.stream',
    issueNumber: 128,
    locatorKind: 'Ceramic stream ID or commit ID',
    handlerURLVariables: ['DBROWSER_CERAMIC_HANDLER_URL'],
    backendVariables: ['CERAMIC_NODE_URL'],
    credentialVariables: [],
    trustBoundary: 'Local Ceramic node loads stream events while the browser preserves DID, commit, and anchor proof verification metadata.',
    verificationRequirements: [
      'Preserve stream ID, commit ID, controller DID, and model hints.',
      'Verify signed commits and anchor proofs before trusting mutable metadata.'
    ],
    requirement: {
      name: 'Ceramic node',
      reason: 'Ceramic streams need event loading, DID signature validation, and anchor proof checks.',
      configurationHint: 'Set DBROWSER_CERAMIC_HANDLER_URL or CERAMIC_NODE_URL.'
    },
    validate: validateNonEmptyLocator,
    buildTarget: buildPathTarget('CERAMIC_NODE_URL', '/api/v0/streams')
  },
  {
    id: 'orbitdb',
    title: 'OrbitDB',
    port: 4891,
    routePath: '/dweb/orbitdb/native',
    schemes: ['orbitdb'],
    handlerID: 'orbitdb.address',
    issueNumber: 129,
    locatorKind: 'OrbitDB address',
    handlerURLVariables: ['DBROWSER_ORBITDB_HANDLER_URL'],
    backendVariables: ['ORBITDB_GATEWAY_URL'],
    credentialVariables: [],
    trustBoundary: 'Local OrbitDB/IPFS runtime owns replication while the browser preserves database address, access-controller, and signed log metadata.',
    verificationRequirements: [
      'Preserve database address, store type, and access-controller metadata.',
      'Verify signed operation log entries before treating collaborative state as trusted.'
    ],
    requirement: {
      name: 'OrbitDB and IPFS replication runtime',
      reason: 'OrbitDB addresses resolve through IPFS/libp2p replication and signed operation logs.',
      configurationHint: 'Set DBROWSER_ORBITDB_HANDLER_URL or ORBITDB_GATEWAY_URL.'
    },
    validate: validateNonEmptyLocator,
    buildTarget: buildPathTarget('ORBITDB_GATEWAY_URL', '/')
  },
  {
    id: 'radicle',
    title: 'Radicle',
    port: 4892,
    routePath: '/dweb/radicle/native',
    schemes: ['rad', 'radicle'],
    handlerID: 'radicle.repository',
    issueNumber: 130,
    locatorKind: 'Radicle repository ID, NID, or URN',
    handlerURLVariables: ['DBROWSER_RADICLE_HANDLER_URL'],
    backendVariables: ['RADICLE_HTTPD_URL'],
    credentialVariables: [],
    trustBoundary: 'Local Radicle node/httpd owns seed discovery and Git object retrieval while the browser preserves repository identity and signed refs metadata.',
    verificationRequirements: [
      'Preserve repository ID, revision, path, and seed hints.',
      'Verify signed refs and expected repository identity before installing code.'
    ],
    requirement: {
      name: 'Radicle node',
      reason: 'Radicle repository URNs require seed discovery, Git object retrieval, and signed ref verification.',
      configurationHint: 'Set DBROWSER_RADICLE_HANDLER_URL or RADICLE_HTTPD_URL.'
    },
    validate: validateNonEmptyLocator,
    buildTarget: buildPathTarget('RADICLE_HTTPD_URL', '/')
  }
];

export const nativeProtocolHandlersByID = new Map(nativeProtocolHandlers.map(handler => [handler.id, handler]));

export function handlerSummary() {
  return nativeProtocolHandlers.map(handler => ({
    id: handler.id,
    title: handler.title,
    port: handler.port,
    routePath: handler.routePath,
    schemes: handler.schemes,
    handlerID: handler.handlerID,
    issueNumber: handler.issueNumber,
    credentialScoped: Boolean(handler.credentialScoped),
    handlerURLVariables: handler.handlerURLVariables,
    backendVariables: handler.backendVariables,
    credentialVariables: handler.credentialVariables
  }));
}

export function resolveNativeAdapterRequest(pathNetworkID, requestURL, env = process.env) {
  const handler = nativeProtocolHandlersByID.get(pathNetworkID);
  if (!handler) {
    return errorResult('invalid', 404, {
      networkID: pathNetworkID,
      message: `No native protocol handler is registered for ${pathNetworkID}.`
    });
  }

  const request = parseAdapterRequest(handler, requestURL);
  const validationErrors = validateRequest(handler, request);
  if (validationErrors.length > 0) {
    return errorResult('invalid', 400, {
      handler,
      request,
      message: validationErrors.join(' ')
    });
  }

  const explicitTarget = buildExplicitHandlerTarget(handler, request, env);
  if (explicitTarget) {
    return successResult(handler, request, explicitTarget);
  }

  const knownTarget = handler.buildTarget?.(handler, request, env) ?? null;
  if (knownTarget?.state === 'credential_required') {
    return requirementResult(handler, request, 'credential_required', 401, knownTarget.message);
  }
  if (knownTarget?.url) {
    return successResult(handler, request, knownTarget);
  }

  return requirementResult(handler, request, 'backend_required', 424, handler.requirement.reason);
}

export function sampleAdapterRequestURL(handlerOrID, scheme = null) {
  const handler = typeof handlerOrID === 'string' ? nativeProtocolHandlersByID.get(handlerOrID) : handlerOrID;
  if (!handler) {
    throw new Error(`unknown handler ${handlerOrID}`);
  }
  const resolvedScheme = scheme ?? handler.schemes[0];
  const uri = sampleURIForScheme(resolvedScheme);
  const requestURL = new URL(`http://${localhost}:${handler.port}${handler.routePath}`);
  requestURL.searchParams.set('network', handler.id);
  requestURL.searchParams.set('scheme', resolvedScheme);
  requestURL.searchParams.set('adapter', handler.handlerID);
  requestURL.searchParams.set('resolution_stage', nativeAdapterStage);
  requestURL.searchParams.set('locator_kind', handler.locatorKind);
  requestURL.searchParams.set('locator', locatorForURI(uri));
  requestURL.searchParams.set('credential_scoped', handler.credentialScoped ? 'true' : 'false');
  requestURL.searchParams.set('native_issue', String(handler.issueNumber));
  requestURL.searchParams.set('uri', uri);
  requestURL.searchParams.set('format', 'json');
  return requestURL;
}

export function sampleURIForScheme(scheme) {
  switch (scheme) {
    case 'filecoin':
      return 'filecoin://baga6ea4seaqnativehandler/app.car';
    case 'piececid':
      return 'piececid://baga6ea4seaqpiecehandler';
    case 'fil':
      return 'fil://f01234/app.car';
    case 'walrus':
      return 'walrus://abc123xyz/site/index.html';
    case 'iroh':
      return 'iroh://blake3examplehash/app.json';
    case 'iroh-blob':
      return 'iroh-blob://blake3examplehash';
    case 'hyper':
    case 'hypercore':
    case 'hyperdrive':
    case 'pear':
    case 'dat':
      return `${scheme}://z6MkhKenNativeFeed/app.json`;
    case 'sia':
      return 'sia://bucket/app.bundle';
    case 'storj':
      return 'storj://apps/demo/app.bundle';
    case 'tahoe':
      return 'tahoe://URI:CHK:secretcap:verifycap:3:10:2048/index.html';
    case 'lafs':
      return 'lafs://URI:CHK:secretcap:verifycap:3:10:2048';
    case 'autonomi':
      return 'autonomi://b3a7appaddress/index.html';
    case 'safe':
      return 'safe://b3a7appaddress/index.html';
    case 'magnet':
      return 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=dBrowser';
    case 'bittorrent':
      return 'bittorrent://0123456789abcdef0123456789abcdef01234567/app.torrent';
    case 'webtorrent':
      return 'webtorrent://0123456789abcdef0123456789abcdef01234567';
    case 'ceramic':
      return 'ceramic://kjzl6cwe1jw145nativehandler';
    case 'ceramic-stream':
      return 'ceramic-stream://kjzl6cwe1jw145nativehandler';
    case 'orbitdb':
      return 'orbitdb://zdpuB1NativeOrbitDB/events';
    case 'rad':
      return 'rad://z3gqcJUoA1n9HaHKufZs5Fcsradrepo/tree/main';
    case 'radicle':
      return 'radicle://z3gqcJUoA1n9HaHKufZs5Fcsradrepo';
    default:
      return `${scheme}://native-handler-example`;
  }
}

function parseAdapterRequest(handler, requestURL) {
  const query = requestURL.searchParams;
  const uri = trim(query.get('uri'));
  const scheme = trim(query.get('scheme')) || safeScheme(uri) || handler.schemes[0];
  const locator = trim(query.get('locator')) || locatorForURI(uri);
  return {
    network: trim(query.get('network')) || handler.id,
    scheme: scheme.toLowerCase(),
    adapter: trim(query.get('adapter')) || handler.handlerID,
    stage: trim(query.get('resolution_stage')) || nativeAdapterStage,
    locatorKind: trim(query.get('locator_kind')) || handler.locatorKind,
    locator,
    credentialScoped: query.get('credential_scoped') === 'true' || Boolean(handler.credentialScoped),
    nativeIssue: trim(query.get('native_issue')) || String(handler.issueNumber),
    uri,
    format: trim(query.get('format')),
    mode: trim(query.get('mode'))
  };
}

function validateRequest(handler, request) {
  const errors = [];
  if (request.network !== handler.id) {
    errors.push(`Network mismatch: path is ${handler.id} but query requested ${request.network}.`);
  }
  if (!handler.schemes.includes(request.scheme)) {
    errors.push(`Scheme ${request.scheme} is not supported by ${handler.id}.`);
  }
  if (request.adapter !== handler.handlerID) {
    errors.push(`Adapter mismatch: expected ${handler.handlerID}.`);
  }
  if (request.stage !== nativeAdapterStage) {
    errors.push(`Resolution stage must be ${nativeAdapterStage}.`);
  }
  if (!request.uri) {
    errors.push('Original URI is required.');
  }
  if (!request.locator) {
    errors.push(`${handler.locatorKind} is required.`);
  }
  if (request.nativeIssue !== String(handler.issueNumber)) {
    errors.push(`Native issue must be ${handler.issueNumber}.`);
  }
  const handlerErrors = handler.validate?.(handler, request) ?? [];
  return errors.concat(handlerErrors);
}

function buildExplicitHandlerTarget(handler, request, env) {
  for (const variable of handler.handlerURLVariables) {
    const base = trim(env[variable]);
    if (!base) {
      continue;
    }
    return {
      url: withAdapterQuery(base, handler, request),
      source: variable,
      proxyMode: 'configured-handler',
      headers: credentialHeaders(handler, env)
    };
  }
  return null;
}

function buildFilecoinTarget(handler, request, env) {
  const base = trim(env.FILECOIN_RETRIEVAL_BASE_URL);
  if (!base) {
    return null;
  }
  return {
    url: appendLocatorPath(base, request.locator),
    source: 'FILECOIN_RETRIEVAL_BASE_URL',
    proxyMode: 'filecoin-retrieval',
    headers: credentialHeaders(handler, env)
  };
}

function buildWalrusTarget(handler, request, env) {
  const locator = splitLocator(request.locator);
  const sitesBase = trim(env.WALRUS_SITES_BASE_URL);
  if (sitesBase && locator.path) {
    return {
      url: appendLocatorPath(sitesBase, `${locator.root}${locator.path}`),
      source: 'WALRUS_SITES_BASE_URL',
      proxyMode: 'walrus-sites',
      headers: {}
    };
  }

  const aggregatorBase = trim(env.WALRUS_AGGREGATOR_BASE_URL);
  if (aggregatorBase && !locator.path) {
    return {
      url: appendLocatorPath(aggregatorBase, `v1/blobs/${locator.root}`),
      source: 'WALRUS_AGGREGATOR_BASE_URL',
      proxyMode: 'walrus-aggregator',
      headers: {}
    };
  }

  return null;
}

function buildSiaTarget(handler, request, env) {
  const base = trim(env.SIA_RENTERD_BASE_URL);
  if (!base) {
    return null;
  }
  const headers = credentialHeaders(handler, env);
  if (Object.keys(headers).length === 0) {
    return {
      state: 'credential_required',
      message: 'SIA_RENTERD_BASE_URL is configured, but no SIA_RENTERD_AUTH_HEADER, SIA_RENTERD_API_TOKEN, or SIA_RENTERD_API_PASSWORD was provided.'
    };
  }
  return {
    url: appendLocatorPath(base, `api/worker/objects/${request.locator}`),
    source: 'SIA_RENTERD_BASE_URL',
    proxyMode: 'sia-renterd',
    headers
  };
}

function buildBitTorrentTarget(handler, request, env) {
  const webSeed = webSeedURL(request.uri);
  if (webSeed) {
    return {
      url: webSeed,
      source: 'magnet-web-seed',
      proxyMode: 'web-seed',
      headers: {}
    };
  }
  return buildFirstPathTarget(['BITTORRENT_ENGINE_URL', 'WEBTORRENT_ENGINE_URL'], '/resolve')(handler, request, env);
}

function buildPathTarget(variable, prefix) {
  return (handler, request, env) => {
    const base = trim(env[variable]);
    if (!base) {
      return null;
    }
    return {
      url: appendLocatorPath(base, joinURLPath(prefix, request.locator)),
      source: variable,
      proxyMode: 'configured-backend',
      headers: credentialHeaders(handler, env)
    };
  };
}

function buildFirstPathTarget(variables, prefix) {
  return (handler, request, env) => {
    for (const variable of variables) {
      const base = trim(env[variable]);
      if (base) {
        return {
          url: appendLocatorPath(base, joinURLPath(prefix, request.locator)),
          source: variable,
          proxyMode: 'configured-backend',
          headers: credentialHeaders(handler, env)
        };
      }
    }
    return null;
  };
}

function successResult(handler, request, target) {
  return baseResult(handler, request, {
    ok: true,
    state: 'ready',
    statusCode: 200,
    message: `${handler.title} native handler is ready through ${target.source}.`,
    target: {
      url: target.url,
      displayURL: redactTargetURL(handler, target.url),
      source: target.source,
      proxyMode: target.proxyMode,
      hasCredentialHeaders: Boolean(target.headers && Object.keys(target.headers).length > 0)
    },
    proxy: {
      url: target.url,
      headers: target.headers ?? {}
    }
  });
}

function requirementResult(handler, request, state, statusCode, message) {
  return baseResult(handler, request, {
    ok: false,
    state,
    statusCode,
    message,
    target: null,
    requirement: {
      name: handler.requirement.name,
      reason: message,
      configurationHint: handler.requirement.configurationHint,
      handlerURLVariables: handler.handlerURLVariables,
      backendVariables: handler.backendVariables,
      credentialVariables: handler.credentialVariables,
      credentialScoped: Boolean(handler.credentialScoped)
    }
  });
}

function errorResult(state, statusCode, payload) {
  const handler = payload.handler;
  const request = payload.request;
  if (handler && request) {
    return baseResult(handler, request, {
      ok: false,
      state,
      statusCode,
      message: payload.message,
      target: null,
      requirement: {
        name: 'Valid native adapter request',
        reason: payload.message,
        configurationHint: 'Use the Swift runtime bridge native adapter URL without altering query metadata.',
        handlerURLVariables: handler.handlerURLVariables,
        backendVariables: handler.backendVariables,
        credentialVariables: handler.credentialVariables,
        credentialScoped: Boolean(handler.credentialScoped)
      }
    });
  }

  return {
    ok: false,
    state,
    statusCode,
    message: payload.message,
    network: { id: payload.networkID },
    contract: handlerContractVersion
  };
}

function baseResult(handler, request, fields) {
  return {
    ok: fields.ok,
    state: fields.state,
    statusCode: fields.statusCode,
    message: fields.message,
    contract: handlerContractVersion,
    network: {
      id: handler.id,
      title: handler.title,
      schemes: handler.schemes
    },
    adapter: {
      id: handler.handlerID,
      stage: nativeAdapterStage,
      routePath: handler.routePath,
      port: handler.port,
      issueNumber: handler.issueNumber
    },
    request: {
      scheme: request.scheme,
      locatorKind: handler.locatorKind,
      locator: handler.secretLocator ? '<redacted>' : request.locator,
      locatorDigest: digest(request.locator),
      originalURI: redactURI(handler, request.uri),
      originalURIDigest: digest(request.uri),
      credentialScoped: Boolean(handler.credentialScoped)
    },
    target: fields.target,
    requirement: fields.requirement ?? null,
    verification: {
      trustBoundary: handler.trustBoundary,
      requirements: handler.verificationRequirements
    },
    proxy: fields.proxy ?? null
  };
}

function validateNonEmptyLocator(_handler, request) {
  return request.locator ? [] : ['Locator is empty.'];
}

function validateTorrentLocator(_handler, request) {
  if (request.scheme === 'magnet') {
    try {
      const url = new URL(request.uri);
      const xt = url.searchParams.get('xt') ?? '';
      if (!/^urn:bt(?:ih|mh):[a-z0-9]+$/i.test(xt)) {
        return ['Magnet links must include a btih or btmh xt parameter.'];
      }
    } catch {
      return ['Magnet URI is not parseable.'];
    }
  }
  return validateNonEmptyLocator(_handler, request);
}

function withAdapterQuery(base, handler, request) {
  const url = new URL(base);
  url.searchParams.set('network', handler.id);
  url.searchParams.set('scheme', request.scheme);
  url.searchParams.set('adapter', handler.handlerID);
  url.searchParams.set('resolution_stage', nativeAdapterStage);
  url.searchParams.set('locator_kind', handler.locatorKind);
  url.searchParams.set('locator', request.locator);
  url.searchParams.set('credential_scoped', handler.credentialScoped ? 'true' : 'false');
  url.searchParams.set('native_issue', String(handler.issueNumber));
  url.searchParams.set('uri', request.uri);
  return url.toString();
}

function appendLocatorPath(base, locator) {
  const url = new URL(base);
  const basePath = url.pathname.replace(/\/+$/, '');
  const locatorPath = String(locator)
    .split('/')
    .filter(Boolean)
    .map(segment => encodeURIComponent(segment))
    .join('/');
  url.pathname = `${basePath}/${locatorPath}`.replace(/\/{2,}/g, '/');
  return url.toString();
}

function joinURLPath(prefix, locator) {
  return [prefix, locator].join('/').replace(/\/{2,}/g, '/');
}

function splitLocator(locator) {
  const [root, ...rest] = String(locator).split('/');
  const path = rest.length > 0 ? `/${rest.join('/')}` : '';
  return { root, path };
}

function credentialHeaders(handler, env) {
  if (trim(env[`${envPrefix(handler.id)}_AUTH_HEADER`])) {
    return parseAuthHeader(env[`${envPrefix(handler.id)}_AUTH_HEADER`]);
  }

  if (handler.id === 'sia') {
    if (trim(env.SIA_RENTERD_AUTH_HEADER)) {
      return parseAuthHeader(env.SIA_RENTERD_AUTH_HEADER);
    }
    if (trim(env.SIA_RENTERD_API_TOKEN)) {
      return { Authorization: `Bearer ${trim(env.SIA_RENTERD_API_TOKEN)}` };
    }
    if (trim(env.SIA_RENTERD_API_PASSWORD)) {
      return { Authorization: `Basic ${Buffer.from(`:${trim(env.SIA_RENTERD_API_PASSWORD)}`).toString('base64')}` };
    }
  }

  return {};
}

function parseAuthHeader(value) {
  const trimmed = trim(value);
  if (!trimmed) {
    return {};
  }
  const index = trimmed.indexOf(':');
  if (index <= 0) {
    return { Authorization: trimmed };
  }
  return { [trimmed.slice(0, index).trim()]: trimmed.slice(index + 1).trim() };
}

function envPrefix(networkID) {
  return `DBROWSER_${networkID.toUpperCase().replace(/[^A-Z0-9]+/g, '_')}`;
}

function locatorForURI(uri) {
  if (!uri) {
    return '';
  }
  try {
    const url = new URL(uri);
    if (url.protocol === 'magnet:') {
      return url.searchParams.get('xt') ?? uri;
    }
    const host = url.hostname || '';
    const path = decodeURIComponent(url.pathname || '').replace(/^\/+/, '');
    return [host, path].filter(Boolean).join('/');
  } catch {
    return uri.replace(/^[a-z][a-z0-9+.-]*:/i, '').replace(/^\/+/, '');
  }
}

function safeScheme(uri) {
  if (!uri) {
    return null;
  }
  const match = uri.match(/^([a-z][a-z0-9+.-]*):/i);
  return match ? match[1].toLowerCase() : null;
}

function webSeedURL(uri) {
  try {
    const url = new URL(uri);
    if (url.protocol !== 'magnet:') {
      return null;
    }
    for (const name of ['as', 'xs', 'ws']) {
      const value = url.searchParams.get(name);
      if (!value) {
        continue;
      }
      const seed = new URL(value);
      if (seed.protocol === 'http:' || seed.protocol === 'https:') {
        return seed.toString();
      }
    }
  } catch {
    return null;
  }
  return null;
}

function redactURI(handler, uri) {
  if (!uri || !handler.secretLocator) {
    return uri;
  }
  const scheme = safeScheme(uri) ?? handler.schemes[0];
  return `${scheme}://<redacted-capability>`;
}

function redactTargetURL(handler, value) {
  if (!value || !handler.secretLocator) {
    return value;
  }
  const url = new URL(value);
  url.pathname = '/<redacted-capability>';
  url.search = '';
  return url.toString();
}

function digest(input) {
  let hash = 0x811c9dc5;
  const value = String(input ?? '');
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return `0x${hash.toString(16).padStart(8, '0')}`;
}

function trim(value) {
  return typeof value === 'string' ? value.trim() : '';
}
