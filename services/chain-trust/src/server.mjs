import crypto from 'node:crypto';
import http from 'node:http';

const args = new Set(process.argv.slice(2));
const port = Number(process.env.CHAIN_TRUST_PORT ?? 4870);
const hostname = process.env.CHAIN_TRUST_HOST ?? '127.0.0.1';
const startedAt = Date.now();
const mode = 'local-fixture';

const genesisHeader = {
  height: 0,
  version: 1,
  previous_block_hash: '0'.repeat(64),
  merkle_root: '4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b',
  timestamp: 1231006505,
  bits: 0x1d00ffff,
  nonce: 2083236893,
  hash: '000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f',
  chain_work: '0000000000000000000000000000000000000000000000000000000100010001',
  source: mode
};

const bitcoinStatus = {
  ok: true,
  service_available: true,
  network: 'mainnet',
  sync_state: 'synced',
  source: mode,
  best_height: genesisHeader.height,
  best_block_hash: genesisHeader.hash,
  best_header: genesisHeader,
  peer_count: 0,
  filter_source: 'fixture-bip157-ready',
  mode
};

const evmChains = {
  'ethereum-mainnet': {
    chain_ref: 'ethereum-mainnet',
    chain_id: 1,
    display_name: 'Ethereum Mainnet',
    finality_model: 'proof-of-stake-finalized',
    sync_state: 'synced'
  },
  'base-mainnet': {
    chain_ref: 'base-mainnet',
    chain_id: 8453,
    display_name: 'Base',
    finality_model: 'rollup-settlement',
    sync_state: 'proof_checked'
  },
  'base-sepolia': {
    chain_ref: 'base-sepolia',
    chain_id: 84532,
    display_name: 'Base Sepolia',
    finality_model: 'rollup-settlement',
    sync_state: 'proof_checked'
  },
  'arbitrum-one': {
    chain_ref: 'arbitrum-one',
    chain_id: 42161,
    display_name: 'Arbitrum One',
    finality_model: 'rollup-settlement',
    sync_state: 'proof_checked'
  },
  'optimism-mainnet': {
    chain_ref: 'optimism-mainnet',
    chain_id: 10,
    display_name: 'Optimism',
    finality_model: 'rollup-settlement',
    sync_state: 'proof_checked'
  },
  'polygon-mainnet': {
    chain_ref: 'polygon-mainnet',
    chain_id: 137,
    display_name: 'Polygon PoS',
    finality_model: 'validator-finality',
    sync_state: 'proof_checked'
  },
  'bnb-smart-chain': {
    chain_ref: 'bnb-smart-chain',
    chain_id: 56,
    display_name: 'BNB Smart Chain',
    finality_model: 'validator-finality',
    sync_state: 'proof_checked'
  },
  'avalanche-c': {
    chain_ref: 'avalanche-c',
    chain_id: 43114,
    display_name: 'Avalanche C-Chain',
    finality_model: 'snowman-finality',
    sync_state: 'proof_checked'
  }
};

const evmFixtureSubject = '0x1111111111111111111111111111111111111111';
const evmFixtureLeaf = evmFixtureLeafHash('account', evmFixtureSubject, '', '0x01');
const evmFixtureReceiptLeaf = evmFixtureLeafHash('receipt', '0xtx-fixture', '', '0x01');
const evmFixtureHeaderHash = sha256HexFromString('ethereum-mainnet|17000000|fixture-header');
const evmFixtureHeader = {
  chain: 'ethereum-mainnet',
  chain_ref: 'ethereum-mainnet',
  number: 17000000,
  hash: evmFixtureHeaderHash,
  parent_hash: sha256HexFromString('ethereum-mainnet|16999999|fixture-header'),
  state_root: evmFixtureLeaf,
  receipts_root: evmFixtureReceiptLeaf,
  transactions_root: sha256HexFromString('ethereum-mainnet|17000000|transactions'),
  timestamp: 1680000000,
  finalized: true,
  source: mode
};

const evmFixtureProof = {
  proof_id: 'evm-fixture-account',
  kind: 'account',
  chain: 'ethereum-mainnet',
  chain_ref: 'ethereum-mainnet',
  subject: evmFixtureSubject,
  expected_value: '0x01',
  block_hash: evmFixtureHeader.hash,
  block_number: evmFixtureHeader.number,
  expected_root: evmFixtureHeader.state_root,
  leaf_hash: evmFixtureLeaf,
  witnesses: [],
  source: mode
};

if (args.has('--snapshot')) {
  console.log(JSON.stringify({
    service: '@browser/chain-trust-service',
    bitcoin: bitcoinStatus,
    evm: evmStatusFor('ethereum-mainnet')
  }, null, 2));
  process.exit(0);
}

if (args.has('--lint')) {
  assertGenesisFixture();
  assertEvmFixture();
  console.log('[chain-trust] schema OK');
  process.exit(0);
}

if (args.has('--self-test')) {
  assertGenesisFixture();
  const result = verifyBitcoinTransaction({
    header: genesisHeader,
    proof: {
      transaction_id: genesisHeader.merkle_root,
      block_hash: genesisHeader.hash,
      merkle_root: genesisHeader.merkle_root,
      transaction_index: 0,
      siblings: []
    }
  });

  if (!result.verified || result.state !== 'synced') {
    console.error('[chain-trust] self-test failed:', result.summary);
    process.exit(1);
  }

  const evmResult = verifyEvmProof({
    header: evmFixtureHeader,
    proof: evmFixtureProof
  });

  if (!evmResult.verified || evmResult.state !== 'synced') {
    console.error('[chain-trust] EVM self-test failed:', evmResult.summary);
    process.exit(1);
  }

  console.log('[chain-trust] self-test complete');
  process.exit(0);
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);

  if (req.method === 'GET' && url.pathname === '/health') {
    return sendJson(res, 200, {
      ok: true,
      uptimeMs: Date.now() - startedAt,
      mode,
      bitcoin: {
        network: bitcoinStatus.network,
        sync_state: bitcoinStatus.sync_state,
        best_height: bitcoinStatus.best_height
      }
    });
  }

  if (req.method === 'GET' && (url.pathname === '/v1/bitcoin/status' || url.pathname === '/bitcoin/status')) {
    return sendJson(res, 200, bitcoinStatus);
  }

  if (req.method === 'GET' && (url.pathname === '/v1/evm/status' || url.pathname === '/evm/status')) {
    return sendJson(res, 200, evmStatusFor(url.searchParams.get('chain')));
  }

  if (req.method === 'POST' && (url.pathname === '/v1/bitcoin/verify-transaction' || url.pathname === '/bitcoin/verify-transaction')) {
    try {
      const payload = await readJson(req);
      return sendJson(res, 200, verifyBitcoinTransaction(payload));
    } catch (err) {
      return sendJson(res, err.statusCode ?? 400, {
        verified: false,
        state: 'failed',
        transaction_id: null,
        block_hash: null,
        height: null,
        summary: String(err.message ?? err)
      });
    }
  }

  if (req.method === 'POST' && (url.pathname === '/v1/evm/verify-proof' || url.pathname === '/evm/verify-proof')) {
    try {
      const payload = await readJson(req);
      return sendJson(res, 200, verifyEvmProof(payload));
    } catch (err) {
      return sendJson(res, err.statusCode ?? 400, {
        verified: false,
        state: 'failed',
        proof_id: null,
        kind: null,
        chain_ref: null,
        block_hash: null,
        block_number: null,
        summary: String(err.message ?? err)
      });
    }
  }

  sendJson(res, 404, { error: 'not found' });
});

server.listen(port, hostname, () => {
  console.log(`[chain-trust] listening on http://${hostname}:${port}`);
});

process.on('SIGINT', () => {
  server.close(() => {
    console.log('[chain-trust] shutdown');
    process.exit(0);
  });
});

function evmStatusFor(requestedChain) {
  const chain = resolveEvmChain(requestedChain);
  const header = {
    ...evmFixtureHeader,
    chain: chain.chain_ref,
    chain_ref: chain.chain_ref,
    finalized: chain.sync_state === 'synced'
  };
  const checkpointKey = chain.sync_state === 'synced' ? 'finalized_checkpoint' : 'head';
  return {
    ok: true,
    service_available: true,
    chain: chain.chain_ref,
    chain_ref: chain.chain_ref,
    chain_id: chain.chain_id,
    sync_state: chain.sync_state,
    source: mode,
    finality_model: chain.finality_model,
    [checkpointKey]: header,
    peer_count: 0,
    proof_source: 'fixture-local-merkle',
    mode
  };
}

function verifyEvmProof(payload) {
  const header = requireObject(payload.header, 'header');
  const proof = requireObject(payload.proof, 'proof');
  const kind = requireString(proof.kind, 'proof.kind');
  if (!['account', 'storage', 'receipt', 'log'].includes(kind)) {
    throw Object.assign(new Error(`unsupported EVM proof kind: ${kind}`), { statusCode: 400 });
  }
  const chainRef = resolveEvmChain(proof.chain_ref ?? proof.chain ?? header.chain_ref ?? header.chain).chain_ref;
  const headerChainRef = resolveEvmChain(header.chain_ref ?? header.chain ?? chainRef).chain_ref;
  const proofID = requireString(proof.proof_id ?? proof.proofID, 'proof.proof_id');
  const blockHash = normalizeHex(requireString(proof.block_hash ?? proof.blockHash, 'proof.block_hash'));
  const headerHash = normalizeHex(requireString(header.hash, 'header.hash'));
  const proofBlockNumber = Number(proof.block_number ?? proof.blockNumber);
  const headerNumber = Number(header.number);

  if (chainRef !== headerChainRef) {
    return evmFailure(proofID, kind, chainRef, blockHash, proofBlockNumber, 'EVM proof chain does not match the execution header.');
  }

  if (blockHash !== headerHash || proofBlockNumber !== headerNumber) {
    return evmFailure(proofID, kind, chainRef, blockHash, proofBlockNumber, 'EVM proof references a different execution block.');
  }

  const headerRoot = normalizeHex(requireString(
    kind === 'account' || kind === 'storage' ? header.state_root ?? header.stateRoot : header.receipts_root ?? header.receiptsRoot,
    `${kind} root`
  ));
  const expectedRoot = normalizeHex(requireString(proof.expected_root ?? proof.expectedRoot, 'proof.expected_root'));
  if (expectedRoot !== headerRoot) {
    return evmFailure(proofID, kind, chainRef, blockHash, proofBlockNumber, `EVM ${kind} proof expected root does not match the header root.`);
  }

  const computedRoot = computeEvmLocalMerkleRoot(
    requireString(proof.leaf_hash ?? proof.leafHash, 'proof.leaf_hash'),
    Array.isArray(proof.witnesses) ? proof.witnesses : []
  );
  if (computedRoot !== headerRoot) {
    return evmFailure(proofID, kind, chainRef, blockHash, proofBlockNumber, `EVM ${kind} proof did not resolve to the expected root.`);
  }

  const finalized = Boolean(header.finalized);
  return {
    verified: true,
    state: finalized && chainRef === 'ethereum-mainnet' ? 'synced' : 'proof_checked',
    proof_id: proofID,
    kind,
    chain_ref: chainRef,
    block_hash: headerHash,
    block_number: Number.isFinite(headerNumber) ? headerNumber : null,
    summary: `EVM ${kind} fixture proof checked for ${chainRef} block ${Number.isFinite(headerNumber) ? headerNumber : 'unknown'}.`
  };
}

function verifyBitcoinTransaction(payload) {
  const header = requireObject(payload.header, 'header');
  const proof = requireObject(payload.proof, 'proof');
  const advertisedHash = normalizeHex(header.hash ?? '');
  const computedHash = computeHeaderHash(header);
  const proofBlockHash = normalizeHex(requireString(proof.block_hash, 'proof.block_hash'));
  const headerMerkleRoot = normalizeHex(requireString(header.merkle_root, 'header.merkle_root'));
  const proofMerkleRoot = normalizeHex(requireString(proof.merkle_root, 'proof.merkle_root'));
  const transactionID = normalizeHex(requireString(proof.transaction_id, 'proof.transaction_id'));
  const height = Number(header.height);

  if (advertisedHash && advertisedHash !== computedHash) {
    return failure(transactionID, proofBlockHash, height, 'Bitcoin header hash does not match its serialized header.');
  }

  if (proofBlockHash !== computedHash) {
    return failure(transactionID, proofBlockHash, height, 'Bitcoin Merkle proof references a different block hash.');
  }

  if (proofMerkleRoot !== headerMerkleRoot) {
    return failure(transactionID, proofBlockHash, height, 'Bitcoin proof Merkle root does not match the header.');
  }

  const computedMerkleRoot = computeMerkleRoot(transactionID, Array.isArray(proof.siblings) ? proof.siblings : []);
  if (computedMerkleRoot !== headerMerkleRoot) {
    return failure(transactionID, proofBlockHash, height, 'Bitcoin Merkle proof did not resolve to the header Merkle root.');
  }

  return {
    verified: true,
    state: 'synced',
    transaction_id: transactionID,
    block_hash: computedHash,
    height: Number.isFinite(height) ? height : null,
    summary: `Bitcoin transaction inclusion verified against header ${Number.isFinite(height) ? height : 'unknown'}.`
  };
}

function computeHeaderHash(header) {
  const buffer = Buffer.alloc(80);
  buffer.writeInt32LE(Number(header.version), 0);
  displayHashToLittleEndian(requireString(header.previous_block_hash, 'header.previous_block_hash')).copy(buffer, 4);
  displayHashToLittleEndian(requireString(header.merkle_root, 'header.merkle_root')).copy(buffer, 36);
  buffer.writeUInt32LE(Number(header.timestamp), 68);
  buffer.writeUInt32LE(Number(header.bits), 72);
  buffer.writeUInt32LE(Number(header.nonce), 76);
  return littleEndianToDisplayHash(doubleSHA256(buffer));
}

function computeMerkleRoot(transactionID, siblings) {
  let node = displayHashToLittleEndian(transactionID);
  for (const sibling of siblings) {
    const siblingHash = displayHashToLittleEndian(requireString(sibling.hash, 'sibling.hash'));
    const position = requireString(sibling.position, 'sibling.position');
    if (position !== 'left' && position !== 'right') {
      throw Object.assign(new Error(`unsupported sibling position: ${position}`), { statusCode: 400 });
    }
    node = position === 'left'
      ? doubleSHA256(Buffer.concat([siblingHash, node]))
      : doubleSHA256(Buffer.concat([node, siblingHash]));
  }
  return littleEndianToDisplayHash(node);
}

function assertGenesisFixture() {
  const computedHash = computeHeaderHash(genesisHeader);
  if (computedHash !== genesisHeader.hash) {
    throw new Error(`genesis fixture mismatch: ${computedHash}`);
  }
}

function assertEvmFixture() {
  const computedRoot = computeEvmLocalMerkleRoot(evmFixtureProof.leaf_hash, evmFixtureProof.witnesses);
  if (computedRoot !== evmFixtureHeader.state_root) {
    throw new Error(`EVM fixture mismatch: ${computedRoot}`);
  }
}

function failure(transactionID, blockHash, height, summary) {
  return {
    verified: false,
    state: 'failed',
    transaction_id: transactionID,
    block_hash: blockHash,
    height: Number.isFinite(height) ? height : null,
    summary
  };
}

function evmFailure(proofID, kind, chainRef, blockHash, blockNumber, summary) {
  return {
    verified: false,
    state: 'failed',
    proof_id: proofID,
    kind,
    chain_ref: chainRef,
    block_hash: blockHash,
    block_number: Number.isFinite(blockNumber) ? blockNumber : null,
    summary
  };
}

function resolveEvmChain(requestedChain) {
  if (!requestedChain) {
    return evmChains['ethereum-mainnet'];
  }
  const normalized = String(requestedChain)
    .trim()
    .toLowerCase()
    .replace(/_/g, '-')
    .replace(/\s+/g, '-');
  if (evmChains[normalized]) {
    return evmChains[normalized];
  }
  const byID = Object.values(evmChains).find(chain => String(chain.chain_id) === normalized);
  return byID ?? evmChains['ethereum-mainnet'];
}

function evmFixtureLeafHash(kind, subject, key, value) {
  return sha256HexFromString([
    kind,
    String(subject).toLowerCase(),
    String(key ?? '').toLowerCase(),
    String(value).toLowerCase()
  ].join('|'));
}

function computeEvmLocalMerkleRoot(leafHash, witnesses) {
  let node = Buffer.from(normalizeHex(leafHash), 'hex');
  for (const witness of witnesses) {
    const siblingHash = Buffer.from(normalizeHex(requireString(witness.hash, 'witness.hash')), 'hex');
    const position = requireString(witness.position, 'witness.position');
    if (position !== 'left' && position !== 'right') {
      throw Object.assign(new Error(`unsupported EVM witness position: ${position}`), { statusCode: 400 });
    }
    node = position === 'left'
      ? crypto.createHash('sha256').update(Buffer.concat([siblingHash, node])).digest()
      : crypto.createHash('sha256').update(Buffer.concat([node, siblingHash])).digest();
  }
  return node.toString('hex');
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => {
      body += chunk;
      if (body.length > 1_000_000) {
        reject(Object.assign(new Error('request body too large'), { statusCode: 413 }));
        req.destroy();
      }
    });
    req.on('end', () => {
      if (!body.trim()) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(body));
      } catch (err) {
        reject(Object.assign(new Error(`invalid JSON: ${err.message}`), { statusCode: 400 }));
      }
    });
    req.on('error', reject);
  });
}

function sendJson(res, status, payload) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload, null, 2));
}

function doubleSHA256(buffer) {
  const first = crypto.createHash('sha256').update(buffer).digest();
  return crypto.createHash('sha256').update(first).digest();
}

function displayHashToLittleEndian(value) {
  return Buffer.from(normalizeHex(value), 'hex').reverse();
}

function littleEndianToDisplayHash(value) {
  return Buffer.from(value).reverse().toString('hex');
}

function sha256HexFromString(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

function normalizeHex(value) {
  const normalized = String(value).trim().toLowerCase().replace(/^0x/, '');
  if (!/^[0-9a-f]*$/.test(normalized) || normalized.length % 2 !== 0) {
    throw Object.assign(new Error(`invalid hex value: ${value}`), { statusCode: 400 });
  }
  return normalized;
}

function requireObject(value, fieldName) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw Object.assign(new Error(`${fieldName} is required`), { statusCode: 400 });
  }
  return value;
}

function requireString(value, fieldName) {
  if (typeof value !== 'string' || !value.trim()) {
    throw Object.assign(new Error(`${fieldName} is required`), { statusCode: 400 });
  }
  return value.trim();
}
