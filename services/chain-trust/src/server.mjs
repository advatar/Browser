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

if (args.has('--snapshot')) {
  console.log(JSON.stringify({ service: '@browser/chain-trust-service', bitcoin: bitcoinStatus }, null, 2));
  process.exit(0);
}

if (args.has('--lint')) {
  assertGenesisFixture();
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
