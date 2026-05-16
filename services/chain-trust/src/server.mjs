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

const avalancheNetworks = {
  'avalanche-c': {
    network: 'avalanche-c',
    chain_ref: 'avalanche-c',
    chain_id: 43114,
    subnet_id: '11111111111111111111111111111111LpoYY',
    vm_id: 'mgj786NP7uDwBCcq6NQ6wW4SnoR14HVoE8Bv7E4s34wToZr3N',
    display_name: 'Avalanche C-Chain',
    finality_model: 'snowman-accepted',
    sync_state: 'proof_checked',
    limitations: ['Fixture-backed accepted-finality checks do not yet replace a production AvalancheGo light client.']
  },
  'avalanche-fuji-c': {
    network: 'avalanche-fuji-c',
    chain_ref: 'avalanche-fuji-c',
    chain_id: 43113,
    subnet_id: '11111111111111111111111111111111LpoYY',
    vm_id: 'mgj786NP7uDwBCcq6NQ6wW4SnoR14HVoE8Bv7E4s34wToZr3N',
    display_name: 'Avalanche Fuji C-Chain',
    finality_model: 'snowman-accepted',
    sync_state: 'rpc_fallback',
    limitations: ['Fuji is modeled for routing and fallback; production local verification is not enabled.']
  }
};
const avalancheValidatorA = 'nodeid-avalanche-fixture-a';
const avalancheValidatorB = 'nodeid-avalanche-fixture-b';
const avalancheValidatorC = 'nodeid-avalanche-fixture-c';
const avalancheFixtureValidators = [
  { node_id: avalancheValidatorA, weight: 50 },
  { node_id: avalancheValidatorB, weight: 30 },
  { node_id: avalancheValidatorC, weight: 20 }
];
const avalancheFixtureValidatorSetHash = avalancheValidatorSetHash(avalancheFixtureValidators);
const avalancheFixtureSubject = '0x2222222222222222222222222222222222222222';
const avalancheFixtureLeaf = evmFixtureLeafHash('account', avalancheFixtureSubject, '', '0x01');
const avalancheFixtureReceiptLeaf = evmFixtureLeafHash('receipt', '0xavalanche-tx-fixture', '', '0x01');
const avalancheFixtureAcceptedBlockHash = sha256HexFromString('avalanche-c|50000000|accepted-block');
const avalancheFixtureAcceptedBlock = {
  network: 'avalanche-c',
  chain_ref: 'avalanche-c',
  chain_id: 43114,
  subnet_id: avalancheNetworks['avalanche-c'].subnet_id,
  vm_id: avalancheNetworks['avalanche-c'].vm_id,
  height: 50000000,
  block_hash: avalancheFixtureAcceptedBlockHash,
  parent_hash: sha256HexFromString('avalanche-c|49999999|accepted-block'),
  state_root: avalancheFixtureLeaf,
  receipts_root: avalancheFixtureReceiptLeaf,
  timestamp: 1710000000,
  accepted: true,
  source: mode
};
const avalancheFixtureValidatorSet = {
  network: 'avalanche-c',
  chain_ref: 'avalanche-c',
  chain_id: 43114,
  set_id: 9001,
  validators: avalancheFixtureValidators,
  hash: avalancheFixtureValidatorSetHash,
  source: mode
};
const avalancheFixtureFinalityEvidence = {
  set_id: avalancheFixtureValidatorSet.set_id,
  target_hash: avalancheFixtureAcceptedBlock.block_hash,
  target_height: avalancheFixtureAcceptedBlock.height,
  signatures: [
    { node_id: avalancheValidatorA, block_hash: avalancheFixtureAcceptedBlock.block_hash, signed: true, signature: 'fixture-snowman-a' },
    { node_id: avalancheValidatorB, block_hash: avalancheFixtureAcceptedBlock.block_hash, signed: true, signature: 'fixture-snowman-b' },
    { node_id: avalancheValidatorC, block_hash: avalancheFixtureAcceptedBlock.block_hash, signed: false, signature: null }
  ],
  source: mode
};
const avalancheFixtureEvmProofBundle = {
  header: {
    chain: 'avalanche-c',
    chain_ref: 'avalanche-c',
    number: avalancheFixtureAcceptedBlock.height,
    hash: avalancheFixtureAcceptedBlock.block_hash,
    parent_hash: avalancheFixtureAcceptedBlock.parent_hash,
    state_root: avalancheFixtureAcceptedBlock.state_root,
    receipts_root: avalancheFixtureAcceptedBlock.receipts_root,
    transactions_root: sha256HexFromString('avalanche-c|50000000|transactions'),
    timestamp: avalancheFixtureAcceptedBlock.timestamp,
    finalized: false,
    source: mode
  },
  proof: {
    proof_id: 'avalanche-fixture-account',
    kind: 'account',
    chain: 'avalanche-c',
    chain_ref: 'avalanche-c',
    subject: avalancheFixtureSubject,
    expected_value: '0x01',
    block_hash: avalancheFixtureAcceptedBlock.block_hash,
    block_number: avalancheFixtureAcceptedBlock.height,
    expected_root: avalancheFixtureAcceptedBlock.state_root,
    leaf_hash: avalancheFixtureLeaf,
    witnesses: [],
    source: mode
  }
};

const solanaClusters = {
  'mainnet-beta': {
    cluster: 'mainnet-beta',
    chain_ref: 'solana-mainnet',
    display_name: 'Solana',
    sync_state: 'synced',
    commitment: 'finalized'
  },
  'solana-mainnet': {
    cluster: 'mainnet-beta',
    chain_ref: 'solana-mainnet',
    display_name: 'Solana',
    sync_state: 'synced',
    commitment: 'finalized'
  },
  devnet: {
    cluster: 'devnet',
    chain_ref: 'solana-devnet',
    display_name: 'Solana Devnet',
    sync_state: 'proof_checked',
    commitment: 'confirmed'
  },
  testnet: {
    cluster: 'testnet',
    chain_ref: 'solana-testnet',
    display_name: 'Solana Testnet',
    sync_state: 'proof_checked',
    commitment: 'confirmed'
  },
  localnet: {
    cluster: 'localnet',
    chain_ref: 'solana-localnet',
    display_name: 'Solana Localnet',
    sync_state: 'proof_checked',
    commitment: 'confirmed'
  }
};
const solanaFixtureSlot = 281474976710;
const solanaFixtureRootSlot = 281474976700;
const solanaFixtureAccount = 'So11111111111111111111111111111111111111112';
const solanaFixtureSignature = '5sUjfixtureTransactionStatus111111111111111111111111111111111';
const solanaFixtureAccountLeaf = solanaFixtureLeafHash('account', solanaFixtureAccount, 'lamports:1');
const solanaFixtureTransactionLeaf = solanaFixtureLeafHash('transaction_status', solanaFixtureSignature, 'confirmed');
const solanaFixtureSlotRoot = {
  cluster: 'mainnet-beta',
  chain_ref: 'solana-mainnet',
  slot: solanaFixtureSlot,
  root_slot: solanaFixtureRootSlot,
  blockhash: sha256HexFromString('solana-mainnet|281474976710|blockhash'),
  parent_slot: solanaFixtureSlot - 1,
  commitment: 'finalized',
  account_root: solanaFixtureAccountLeaf,
  transaction_status_root: solanaFixtureTransactionLeaf,
  source: mode
};
const solanaFixtureProof = {
  proof_id: 'solana-fixture-account',
  kind: 'account',
  cluster: 'mainnet-beta',
  chain_ref: 'solana-mainnet',
  subject: solanaFixtureAccount,
  slot: solanaFixtureSlot,
  expected_root: solanaFixtureSlotRoot.account_root,
  leaf_hash: solanaFixtureAccountLeaf,
  witnesses: [],
  source: mode
};

const cosmosChains = {
  'cosmoshub-4': {
    chain: 'cosmoshub-4',
    chain_id: 'cosmoshub-4',
    chain_ref: 'cosmos-hub',
    display_name: 'Cosmos Hub',
    bech32_prefix: 'cosmos',
    sync_state: 'synced',
    trust_period_seconds: 1209600
  },
  'cosmos-hub': {
    chain: 'cosmoshub-4',
    chain_id: 'cosmoshub-4',
    chain_ref: 'cosmos-hub',
    display_name: 'Cosmos Hub',
    bech32_prefix: 'cosmos',
    sync_state: 'synced',
    trust_period_seconds: 1209600
  },
  'osmosis-1': {
    chain: 'osmosis-1',
    chain_id: 'osmosis-1',
    chain_ref: 'osmosis',
    display_name: 'Osmosis',
    bech32_prefix: 'osmo',
    sync_state: 'proof_checked',
    trust_period_seconds: 1209600
  },
  osmosis: {
    chain: 'osmosis-1',
    chain_id: 'osmosis-1',
    chain_ref: 'osmosis',
    display_name: 'Osmosis',
    bech32_prefix: 'osmo',
    sync_state: 'proof_checked',
    trust_period_seconds: 1209600
  },
  'juno-1': {
    chain: 'juno-1',
    chain_id: 'juno-1',
    chain_ref: 'juno',
    display_name: 'Juno',
    bech32_prefix: 'juno',
    sync_state: 'proof_checked',
    trust_period_seconds: 1209600
  }
};
const cosmosValidatorA = 'a1'.repeat(20);
const cosmosValidatorB = 'b2'.repeat(20);
const cosmosValidatorC = 'c3'.repeat(20);
const cosmosFixtureValidators = [
  { address: cosmosValidatorA, public_key: 'cosmos-pubkey-a', voting_power: 40, name: 'validator-a' },
  { address: cosmosValidatorB, public_key: 'cosmos-pubkey-b', voting_power: 35, name: 'validator-b' },
  { address: cosmosValidatorC, public_key: 'cosmos-pubkey-c', voting_power: 25, name: 'validator-c' }
];
const cosmosFixtureValidatorSetHash = tendermintValidatorSetHash(cosmosFixtureValidators);
const cosmosFixtureHeader = {
  chain: 'cosmoshub-4',
  chain_ref: 'cosmos-hub',
  chain_id: 'cosmoshub-4',
  height: 19700000,
  time_unix_seconds: 1778889600,
  last_block_id_hash: sha256HexFromString('cosmoshub-4|19699999'),
  validators_hash: cosmosFixtureValidatorSetHash,
  next_validators_hash: cosmosFixtureValidatorSetHash,
  app_hash: sha256HexFromString('cosmoshub-4|19700000|app'),
  data_hash: sha256HexFromString('cosmoshub-4|19700000|data'),
  evidence_hash: sha256HexFromString('cosmoshub-4|19700000|evidence'),
  proposer_address: cosmosValidatorA,
  source: mode
};
const cosmosFixtureHeaderHash = tendermintHeaderHash(cosmosFixtureHeader);
const cosmosFixtureValidatorSet = {
  chain: 'cosmoshub-4',
  chain_ref: 'cosmos-hub',
  chain_id: 'cosmoshub-4',
  height: cosmosFixtureHeader.height,
  validators: cosmosFixtureValidators,
  hash: cosmosFixtureValidatorSetHash,
  source: mode
};
const cosmosFixtureCommit = {
  height: cosmosFixtureHeader.height,
  round: 0,
  block_id_hash: cosmosFixtureHeaderHash,
  signatures: [
    { validator_address: cosmosValidatorA, block_id_hash: cosmosFixtureHeaderHash, signed: true, signature: 'fixture-sig-a' },
    { validator_address: cosmosValidatorB, block_id_hash: cosmosFixtureHeaderHash, signed: true, signature: 'fixture-sig-b' },
    { validator_address: cosmosValidatorC, block_id_hash: cosmosFixtureHeaderHash, signed: false, signature: null }
  ],
  source: mode
};
const cosmosFixtureTrustPolicy = {
  trusted_height: cosmosFixtureHeader.height - 10,
  trusted_time_unix_seconds: 4101235200,
  trust_period_seconds: 1209600
};

const substrateChains = {
  polkadot: {
    chain: 'polkadot',
    chain_ref: 'polkadot',
    chain_spec_id: 'polkadot',
    display_name: 'Polkadot',
    sync_state: 'synced'
  },
  kusama: {
    chain: 'kusama',
    chain_ref: 'kusama',
    chain_spec_id: 'kusama',
    display_name: 'Kusama',
    sync_state: 'proof_checked'
  },
  westend: {
    chain: 'westend',
    chain_ref: 'westend',
    chain_spec_id: 'westend',
    display_name: 'Westend',
    sync_state: 'proof_checked'
  },
  'asset-hub-polkadot': {
    chain: 'asset-hub-polkadot',
    chain_ref: 'asset-hub-polkadot',
    chain_spec_id: 'asset-hub-polkadot',
    display_name: 'Asset Hub Polkadot',
    sync_state: 'proof_checked'
  }
};
const substrateAuthorityA = 'd1'.repeat(16);
const substrateAuthorityB = 'e2'.repeat(16);
const substrateAuthorityC = 'f3'.repeat(16);
const substrateFixtureAuthorities = [
  { authority_id: substrateAuthorityA, weight: 40 },
  { authority_id: substrateAuthorityB, weight: 35 },
  { authority_id: substrateAuthorityC, weight: 25 }
];
const substrateFixtureAuthoritySetHash = grandpaAuthoritySetHash(substrateFixtureAuthorities);
const substrateFixtureStorageKey = '0x26aa394eea5630e07c48ae0c9558cef7';
const substrateFixtureValueHash = sha256HexFromString('polkadot-account-balance:1');
const substrateFixtureLeafHash = substrateFixtureStorageLeafHash(substrateFixtureStorageKey, substrateFixtureValueHash);
const substrateFixtureStateRoot = substrateFixtureLeafHash;
const substrateFixtureHeaderHash = sha256HexFromString('polkadot|21000000|fixture-header');
const substrateFixtureHeader = {
  chain: 'polkadot',
  chain_ref: 'polkadot',
  chain_spec_id: 'polkadot',
  number: 21000000,
  hash: substrateFixtureHeaderHash,
  parent_hash: sha256HexFromString('polkadot|20999999|fixture-header'),
  state_root: substrateFixtureStateRoot,
  extrinsics_root: sha256HexFromString('polkadot|21000000|extrinsics'),
  digest_logs: ['0x0642414245'],
  finalized: true,
  source: mode
};
const substrateFixtureAuthoritySet = {
  chain: 'polkadot',
  chain_ref: 'polkadot',
  chain_spec_id: 'polkadot',
  set_id: 1234,
  authorities: substrateFixtureAuthorities,
  hash: substrateFixtureAuthoritySetHash,
  source: mode
};
const substrateFixtureJustification = {
  round: 42,
  set_id: substrateFixtureAuthoritySet.set_id,
  target_hash: substrateFixtureHeader.hash,
  target_number: substrateFixtureHeader.number,
  signatures: [
    { authority_id: substrateAuthorityA, block_hash: substrateFixtureHeader.hash, signed: true, signature: 'fixture-grandpa-a' },
    { authority_id: substrateAuthorityB, block_hash: substrateFixtureHeader.hash, signed: true, signature: 'fixture-grandpa-b' },
    { authority_id: substrateAuthorityC, block_hash: substrateFixtureHeader.hash, signed: false, signature: null }
  ],
  source: mode
};
const substrateFixtureStorageProof = {
  proof_id: 'substrate-fixture-storage',
  chain: 'polkadot',
  chain_ref: 'polkadot',
  chain_spec_id: 'polkadot',
  block_hash: substrateFixtureHeader.hash,
  storage_key: substrateFixtureStorageKey,
  expected_value_hash: substrateFixtureValueHash,
  leaf_hash: substrateFixtureLeafHash,
  witnesses: [],
  source: mode
};

if (args.has('--snapshot')) {
  console.log(JSON.stringify({
    service: '@browser/chain-trust-service',
    bitcoin: bitcoinStatus,
    evm: evmStatusFor('ethereum-mainnet'),
    avalanche: avalancheStatusFor('avalanche-c'),
    solana: solanaStatusFor('mainnet-beta'),
    cosmos: cosmosStatusFor('cosmoshub-4'),
    substrate: substrateStatusFor('polkadot')
  }, null, 2));
  process.exit(0);
}

if (args.has('--lint')) {
  assertGenesisFixture();
  assertEvmFixture();
  assertAvalancheFixture();
  assertSolanaFixture();
  assertCosmosFixture();
  assertSubstrateFixture();
  console.log('[chain-trust] schema OK');
  process.exit(0);
}

if (args.has('--self-test')) {
  assertGenesisFixture();
  assertEvmFixture();
  assertAvalancheFixture();
  assertSolanaFixture();
  assertCosmosFixture();
  assertSubstrateFixture();
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

  const avalancheResult = verifyAvalancheState({
    accepted_block: avalancheFixtureAcceptedBlock,
    validator_set: avalancheFixtureValidatorSet,
    finality_evidence: avalancheFixtureFinalityEvidence,
    evm_proof: avalancheFixtureEvmProofBundle
  });

  if (!avalancheResult.verified || avalancheResult.state !== 'proof_checked') {
    console.error('[chain-trust] Avalanche self-test failed:', avalancheResult.summary);
    process.exit(1);
  }

  const solanaResult = verifySolanaProof({
    snapshot: solanaFixtureSlotRoot,
    proof: solanaFixtureProof
  });

  if (!solanaResult.verified || solanaResult.state !== 'synced') {
    console.error('[chain-trust] Solana self-test failed:', solanaResult.summary);
    process.exit(1);
  }

  const cosmosResult = verifyCosmosHeader({
    header: cosmosFixtureHeader,
    validator_set: cosmosFixtureValidatorSet,
    commit: cosmosFixtureCommit,
    trust_policy: cosmosFixtureTrustPolicy
  });

  if (!cosmosResult.verified || cosmosResult.state !== 'synced') {
    console.error('[chain-trust] Cosmos self-test failed:', cosmosResult.summary);
    process.exit(1);
  }

  const substrateResult = verifySubstrateStorageProof({
    header: substrateFixtureHeader,
    authority_set: substrateFixtureAuthoritySet,
    justification: substrateFixtureJustification,
    storage_proof: substrateFixtureStorageProof
  });

  if (!substrateResult.verified || substrateResult.state !== 'synced') {
    console.error('[chain-trust] Substrate self-test failed:', substrateResult.summary);
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

  if (req.method === 'GET' && (url.pathname === '/v1/avalanche/status' || url.pathname === '/avalanche/status')) {
    return sendJson(res, 200, avalancheStatusFor(url.searchParams.get('network')));
  }

  if (req.method === 'GET' && (url.pathname === '/v1/solana/status' || url.pathname === '/solana/status')) {
    return sendJson(res, 200, solanaStatusFor(url.searchParams.get('cluster')));
  }

  if (req.method === 'GET' && (url.pathname === '/v1/cosmos/status' || url.pathname === '/cosmos/status')) {
    return sendJson(res, 200, cosmosStatusFor(url.searchParams.get('chain')));
  }

  if (req.method === 'GET' && (url.pathname === '/v1/substrate/status' || url.pathname === '/substrate/status')) {
    return sendJson(res, 200, substrateStatusFor(url.searchParams.get('chain')));
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

  if (req.method === 'POST' && (url.pathname === '/v1/avalanche/verify-state' || url.pathname === '/avalanche/verify-state')) {
    try {
      const payload = await readJson(req);
      return sendJson(res, 200, verifyAvalancheState(payload));
    } catch (err) {
      return sendJson(res, err.statusCode ?? 400, {
        verified: false,
        state: 'failed',
        chain_ref: null,
        block_number: null,
        block_hash: null,
        proof_id: null,
        summary: String(err.message ?? err)
      });
    }
  }

  if (req.method === 'POST' && (url.pathname === '/v1/solana/verify-proof' || url.pathname === '/solana/verify-proof')) {
    try {
      const payload = await readJson(req);
      return sendJson(res, 200, verifySolanaProof(payload));
    } catch (err) {
      return sendJson(res, err.statusCode ?? 400, {
        verified: false,
        state: 'failed',
        proof_id: null,
        kind: null,
        chain_ref: null,
        slot: null,
        root_slot: null,
        summary: String(err.message ?? err)
      });
    }
  }

  if (req.method === 'POST' && (url.pathname === '/v1/cosmos/verify-header' || url.pathname === '/cosmos/verify-header')) {
    try {
      const payload = await readJson(req);
      return sendJson(res, 200, verifyCosmosHeader(payload));
    } catch (err) {
      return sendJson(res, err.statusCode ?? 400, {
        verified: false,
        state: 'failed',
        chain_ref: null,
        chain_id: null,
        height: null,
        block_hash: null,
        validator_set_hash: null,
        summary: String(err.message ?? err)
      });
    }
  }

  if (req.method === 'POST' && (url.pathname === '/v1/substrate/verify-storage-proof' || url.pathname === '/substrate/verify-storage-proof')) {
    try {
      const payload = await readJson(req);
      return sendJson(res, 200, verifySubstrateStorageProof(payload));
    } catch (err) {
      return sendJson(res, err.statusCode ?? 400, {
        verified: false,
        state: 'failed',
        chain_ref: null,
        chain_spec_id: null,
        block_number: null,
        block_hash: null,
        proof_id: null,
        storage_key: null,
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

function avalancheStatusFor(requestedNetwork) {
  const network = resolveAvalancheNetwork(requestedNetwork);
  const acceptedBlock = {
    ...avalancheFixtureAcceptedBlock,
    network: network.network,
    chain_ref: network.chain_ref,
    chain_id: network.chain_id,
    subnet_id: network.subnet_id,
    vm_id: network.vm_id,
    accepted: network.sync_state !== 'rpc_fallback'
  };
  const validatorSet = {
    ...avalancheFixtureValidatorSet,
    network: network.network,
    chain_ref: network.chain_ref,
    chain_id: network.chain_id
  };
  return {
    ok: true,
    service_available: network.sync_state !== 'rpc_fallback',
    network: network.network,
    chain_ref: network.chain_ref,
    chain_id: network.chain_id,
    sync_state: network.sync_state,
    source: mode,
    finality_model: network.finality_model,
    accepted_block: acceptedBlock,
    validator_set: validatorSet,
    peer_count: 0,
    proof_source: 'fixture-snowman-evm-proof',
    limitations: network.limitations,
    mode
  };
}

function solanaStatusFor(requestedCluster) {
  const cluster = resolveSolanaCluster(requestedCluster);
  const slotRoot = {
    ...solanaFixtureSlotRoot,
    cluster: cluster.cluster,
    chain_ref: cluster.chain_ref,
    commitment: cluster.commitment
  };
  return {
    ok: true,
    service_available: true,
    cluster: cluster.cluster,
    chain_ref: cluster.chain_ref,
    sync_state: cluster.sync_state,
    source: mode,
    slot_root: slotRoot,
    peer_count: 0,
    proof_source: 'fixture-local-merkle',
    root_lag: slotRoot.slot - slotRoot.root_slot,
    max_root_lag: 512,
    mode
  };
}

function cosmosStatusFor(requestedChain) {
  const chain = resolveCosmosChain(requestedChain);
  const header = {
    ...cosmosFixtureHeader,
    chain: chain.chain,
    chain_ref: chain.chain_ref,
    chain_id: chain.chain_id
  };
  const validatorSet = {
    ...cosmosFixtureValidatorSet,
    chain: chain.chain,
    chain_ref: chain.chain_ref,
    chain_id: chain.chain_id
  };
  return {
    ok: true,
    service_available: true,
    chain: chain.chain,
    chain_ref: chain.chain_ref,
    chain_id: chain.chain_id,
    sync_state: chain.sync_state,
    source: mode,
    latest_header: header,
    validator_set: validatorSet,
    peer_count: 0,
    proof_source: 'fixture-tendermint-commit',
    trust_period_expired: false,
    trust_expires_at_unix_seconds: cosmosFixtureTrustPolicy.trusted_time_unix_seconds + chain.trust_period_seconds,
    mode
  };
}

function substrateStatusFor(requestedChain) {
  const chain = resolveSubstrateChain(requestedChain);
  const header = {
    ...substrateFixtureHeader,
    chain: chain.chain,
    chain_ref: chain.chain_ref,
    chain_spec_id: chain.chain_spec_id,
    finalized: chain.sync_state === 'synced'
  };
  const authoritySet = {
    ...substrateFixtureAuthoritySet,
    chain: chain.chain,
    chain_ref: chain.chain_ref,
    chain_spec_id: chain.chain_spec_id
  };
  return {
    ok: true,
    service_available: true,
    chain: chain.chain,
    chain_ref: chain.chain_ref,
    chain_spec_id: chain.chain_spec_id,
    sync_state: chain.sync_state,
    source: mode,
    latest_finalized_header: header,
    authority_set: authoritySet,
    peer_count: 0,
    proof_source: 'fixture-grandpa-storage',
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

function verifyAvalancheState(payload) {
  const acceptedBlock = requireObject(payload.accepted_block ?? payload.acceptedBlock, 'accepted_block');
  const validatorSet = requireObject(payload.validator_set ?? payload.validatorSet, 'validator_set');
  const finalityEvidence = requireObject(payload.finality_evidence ?? payload.finalityEvidence, 'finality_evidence');
  const evmProof = payload.evm_proof ?? payload.evmProof;
  const network = resolveAvalancheNetwork(acceptedBlock.network ?? acceptedBlock.chain_ref ?? acceptedBlock.chainID ?? acceptedBlock.chain_id);
  const validatorSetNetwork = resolveAvalancheNetwork(validatorSet.network ?? validatorSet.chain_ref ?? validatorSet.chainID ?? validatorSet.chain_id ?? network.network);
  const height = Number(acceptedBlock.height);
  const blockHash = normalizeHex(requireString(acceptedBlock.block_hash ?? acceptedBlock.blockHash, 'accepted_block.block_hash'));
  const validatorSetHash = normalizeHex(requireString(validatorSet.hash, 'validator_set.hash'));
  const computedValidatorSetHash = avalancheValidatorSetHash(Array.isArray(validatorSet.validators) ? validatorSet.validators : []);
  const setID = Number(validatorSet.set_id ?? validatorSet.setID);
  const evidenceSetID = Number(finalityEvidence.set_id ?? finalityEvidence.setID);
  const evidenceHeight = Number(finalityEvidence.target_height ?? finalityEvidence.targetHeight);
  const evidenceHash = normalizeHex(requireString(finalityEvidence.target_hash ?? finalityEvidence.targetHash, 'finality_evidence.target_hash'));

  if (network.chain_ref !== validatorSetNetwork.chain_ref) {
    return avalancheFailure(network, height, blockHash, evmProof, 'Avalanche accepted block network does not match the validator set.');
  }
  if (acceptedBlock.accepted === false) {
    return avalancheFailure(network, height, blockHash, evmProof, 'Avalanche block is not marked accepted by Snowman finality evidence.');
  }
  if (setID !== evidenceSetID) {
    return avalancheFailure(network, height, blockHash, evmProof, 'Avalanche finality evidence uses a different validator set.');
  }
  if (evidenceHeight !== height || evidenceHash !== blockHash) {
    return avalancheFailure(network, height, blockHash, evmProof, 'Avalanche finality evidence targets a different accepted block.');
  }
  if (validatorSetHash !== computedValidatorSetHash) {
    return avalancheFailure(network, height, blockHash, evmProof, 'Avalanche validator set hash is invalid.');
  }

  const conflictingEvidence = payload.conflicting_evidence ?? payload.conflictingEvidence;
  if (conflictingEvidence) {
    const conflictHeight = Number(conflictingEvidence.target_height ?? conflictingEvidence.targetHeight);
    const conflictHash = normalizeHex(requireString(conflictingEvidence.target_hash ?? conflictingEvidence.targetHash, 'conflicting_evidence.target_hash'));
    if (conflictHeight === height
        && conflictHash !== evidenceHash
        && hasAvalancheAcceptedQuorum(validatorSet.validators, avalancheSignedValidators(conflictingEvidence))) {
      return avalancheFailure(network, height, blockHash, evmProof, 'Conflicting Avalanche accepted-block evidence reached validator quorum.');
    }
  }

  if (!hasAvalancheAcceptedQuorum(validatorSet.validators, avalancheSignedValidators(finalityEvidence))) {
    return avalancheFailure(network, height, blockHash, evmProof, 'Avalanche accepted-finality evidence did not reach the validator-weight quorum.');
  }

  if (evmProof) {
    const header = requireObject(evmProof.header, 'evm_proof.header');
    const proof = requireObject(evmProof.proof, 'evm_proof.proof');
    const proofChain = resolveEvmChain(proof.chain_ref ?? proof.chain ?? header.chain_ref ?? header.chain);
    const headerChain = resolveEvmChain(header.chain_ref ?? header.chain ?? proofChain.chain_ref);
    const headerHash = normalizeHex(requireString(header.hash, 'evm_proof.header.hash'));
    const headerNumber = Number(header.number);
    const stateRoot = normalizeHex(requireString(acceptedBlock.state_root ?? acceptedBlock.stateRoot, 'accepted_block.state_root'));
    const receiptsRoot = normalizeHex(requireString(acceptedBlock.receipts_root ?? acceptedBlock.receiptsRoot, 'accepted_block.receipts_root'));
    if (proofChain.chain_ref !== 'avalanche-c' || headerChain.chain_ref !== 'avalanche-c') {
      return avalancheFailure(network, height, blockHash, evmProof, 'C-Chain EVM proof must be Avalanche-specific and must not use Ethereum mainnet finality.');
    }
    if (headerHash !== blockHash
        || headerNumber !== height
        || normalizeHex(requireString(header.state_root ?? header.stateRoot, 'evm_proof.header.state_root')) !== stateRoot
        || normalizeHex(requireString(header.receipts_root ?? header.receiptsRoot, 'evm_proof.header.receipts_root')) !== receiptsRoot) {
      return avalancheFailure(network, height, blockHash, evmProof, 'C-Chain EVM proof header is not bound to the accepted Avalanche block.');
    }
    const evmResult = verifyEvmProof(evmProof);
    if (!evmResult.verified) {
      return avalancheFailure(network, height, blockHash, evmProof, evmResult.summary);
    }
  }

  return {
    verified: true,
    state: 'proof_checked',
    chain_ref: network.chain_ref,
    block_number: Number.isFinite(height) ? height : null,
    block_hash: blockHash,
    proof_id: evmProof?.proof ? String(evmProof.proof.proof_id ?? evmProof.proof.proofID ?? '') : null,
    summary: evmProof
      ? `Avalanche Snowman accepted block ${Number.isFinite(height) ? height : 'unknown'} checked with C-Chain EVM proof evidence.`
      : `Avalanche Snowman accepted block ${Number.isFinite(height) ? height : 'unknown'} checked with fixture validator quorum.`
  };
}

function verifySolanaProof(payload) {
  const snapshot = requireObject(payload.snapshot, 'snapshot');
  const proof = requireObject(payload.proof, 'proof');
  const kind = requireString(proof.kind, 'proof.kind');
  if (!['account', 'transaction_status'].includes(kind)) {
    throw Object.assign(new Error(`unsupported Solana proof kind: ${kind}`), { statusCode: 400 });
  }

  const proofID = requireString(proof.proof_id ?? proof.proofID, 'proof.proof_id');
  const cluster = resolveSolanaCluster(proof.chain_ref ?? proof.cluster ?? snapshot.chain_ref ?? snapshot.cluster);
  const snapshotCluster = resolveSolanaCluster(snapshot.chain_ref ?? snapshot.cluster ?? cluster.cluster);
  const proofSlot = Number(proof.slot);
  const snapshotSlot = Number(snapshot.slot);
  const rootSlot = Number(snapshot.root_slot ?? snapshot.rootSlot);

  if (cluster.chain_ref !== snapshotCluster.chain_ref) {
    return solanaFailure(proofID, kind, cluster.chain_ref, proofSlot, rootSlot, 'Solana proof cluster does not match the slot/root snapshot.');
  }

  if (!Number.isFinite(proofSlot) || !Number.isFinite(snapshotSlot) || !Number.isFinite(rootSlot)) {
    return solanaFailure(proofID, kind, cluster.chain_ref, proofSlot, rootSlot, 'Solana proof slot/root fields are invalid.');
  }

  if (proofSlot > snapshotSlot) {
    return solanaFailure(proofID, kind, cluster.chain_ref, proofSlot, rootSlot, 'Solana proof references a future slot.');
  }

  const snapshotRoot = normalizeHex(requireString(
    kind === 'account'
      ? snapshot.account_root ?? snapshot.accountRoot
      : snapshot.transaction_status_root ?? snapshot.transactionStatusRoot,
    `${kind} root`
  ));
  const expectedRoot = normalizeHex(requireString(proof.expected_root ?? proof.expectedRoot, 'proof.expected_root'));
  if (expectedRoot !== snapshotRoot) {
    return solanaFailure(proofID, kind, cluster.chain_ref, proofSlot, rootSlot, `Solana ${kind} proof expected root does not match the snapshot root.`);
  }

  const computedRoot = computeSolanaLocalMerkleRoot(
    requireString(proof.leaf_hash ?? proof.leafHash, 'proof.leaf_hash'),
    Array.isArray(proof.witnesses) ? proof.witnesses : []
  );
  if (computedRoot !== snapshotRoot) {
    return solanaFailure(proofID, kind, cluster.chain_ref, proofSlot, rootSlot, `Solana ${kind} proof did not resolve to the expected root.`);
  }

  const maxRootLag = Number(payload.max_root_lag ?? payload.maxRootLag ?? 512);
  const rootLag = snapshotSlot >= rootSlot ? snapshotSlot - rootSlot : 0;
  const finalized = String(snapshot.commitment ?? '').toLowerCase() === 'finalized';
  return {
    verified: true,
    state: finalized && rootLag <= maxRootLag ? 'synced' : 'proof_checked',
    proof_id: proofID,
    kind,
    chain_ref: cluster.chain_ref,
    slot: proofSlot,
    root_slot: rootSlot,
    summary: `Solana ${kind} fixture proof checked at slot ${Number.isFinite(proofSlot) ? proofSlot : 'unknown'}.`
  };
}

function verifyCosmosHeader(payload) {
  const header = requireObject(payload.header, 'header');
  const validatorSet = requireObject(payload.validator_set ?? payload.validatorSet, 'validator_set');
  const commit = requireObject(payload.commit, 'commit');
  const trustPolicy = payload.trust_policy ?? payload.trustPolicy ?? cosmosFixtureTrustPolicy;
  const chain = resolveCosmosChain(header.chain_id ?? header.chain_ref ?? header.chain);
  const validatorSetChain = resolveCosmosChain(validatorSet.chain_id ?? validatorSet.chain_ref ?? validatorSet.chain ?? chain.chain_id);
  const height = Number(header.height);
  const commitHeight = Number(commit.height);
  const validatorSetHash = normalizeHex(requireString(validatorSet.hash, 'validator_set.hash'));
  const computedValidatorSetHash = tendermintValidatorSetHash(Array.isArray(validatorSet.validators) ? validatorSet.validators : []);
  const headerValidatorsHash = normalizeHex(requireString(header.validators_hash ?? header.validatorsHash, 'header.validators_hash'));
  const headerHash = tendermintHeaderHash(header);
  const commitBlockHash = normalizeHex(requireString(commit.block_id_hash ?? commit.blockIDHash, 'commit.block_id_hash'));

  if (chain.chain_ref !== validatorSetChain.chain_ref) {
    return cosmosFailure(chain, height, headerHash, validatorSetHash, 'Tendermint header chain does not match validator set chain.');
  }

  if (!Number.isFinite(height) || height !== commitHeight) {
    return cosmosFailure(chain, height, headerHash, validatorSetHash, 'Tendermint commit height does not match the header height.');
  }

  if (commitBlockHash !== headerHash) {
    return cosmosFailure(chain, height, headerHash, validatorSetHash, 'Tendermint commit signed a different block ID.');
  }

  if (validatorSetHash !== computedValidatorSetHash || headerValidatorsHash !== validatorSetHash) {
    return cosmosFailure(chain, height, headerHash, validatorSetHash, 'Tendermint validator set hash does not match the header.');
  }

  const now = Math.floor(Date.now() / 1000);
  const trustedTime = Number(trustPolicy.trusted_time_unix_seconds ?? trustPolicy.trustedTimeUnixSeconds ?? 0);
  const trustPeriod = Number(trustPolicy.trust_period_seconds ?? trustPolicy.trustPeriodSeconds ?? chain.trust_period_seconds);
  if (Number.isFinite(trustedTime) && Number.isFinite(trustPeriod) && now > trustedTime + trustPeriod) {
    return {
      verified: false,
      state: 'stale',
      chain_ref: chain.chain_ref,
      chain_id: chain.chain_id,
      height: Number.isFinite(height) ? height : null,
      block_hash: headerHash,
      validator_set_hash: validatorSetHash,
      summary: 'Tendermint trusted period expired before this header could be verified.'
    };
  }

  const conflictingCommit = payload.conflicting_commit ?? payload.conflictingCommit;
  if (conflictingCommit) {
    const conflictHeight = Number(conflictingCommit.height);
    const conflictBlockHash = normalizeHex(requireString(conflictingCommit.block_id_hash ?? conflictingCommit.blockIDHash, 'conflicting_commit.block_id_hash'));
    if (conflictHeight === height
        && conflictBlockHash !== commitBlockHash
        && hasTendermintTwoThirdsPower(validatorSet.validators, signedAddresses(conflictingCommit))) {
      return cosmosFailure(chain, height, headerHash, validatorSetHash, 'Conflicting Tendermint commits both reached the voting-power threshold.');
    }
  }

  if (!hasTendermintTwoThirdsPower(validatorSet.validators, signedAddresses(commit))) {
    return cosmosFailure(chain, height, headerHash, validatorSetHash, 'Tendermint commit did not reach the two-thirds voting-power threshold.');
  }

  return {
    verified: true,
    state: chain.chain_ref === 'cosmos-hub' ? 'synced' : 'proof_checked',
    chain_ref: chain.chain_ref,
    chain_id: chain.chain_id,
    height: Number.isFinite(height) ? height : null,
    block_hash: headerHash,
    validator_set_hash: validatorSetHash,
    summary: `Tendermint header ${Number.isFinite(height) ? height : 'unknown'} verified with two-thirds validator power.`
  };
}

function verifySubstrateStorageProof(payload) {
  const header = requireObject(payload.header, 'header');
  const authoritySet = requireObject(payload.authority_set ?? payload.authoritySet, 'authority_set');
  const justification = requireObject(payload.justification, 'justification');
  const storageProof = payload.storage_proof ?? payload.storageProof;
  const chain = resolveSubstrateChain(header.chain_spec_id ?? header.chain_ref ?? header.chain);
  const authoritySetChain = resolveSubstrateChain(authoritySet.chain_spec_id ?? authoritySet.chain_ref ?? authoritySet.chain ?? chain.chain_spec_id);
  const blockNumber = Number(header.number);
  const blockHash = normalizeHex(requireString(header.hash, 'header.hash'));
  const stateRoot = normalizeHex(requireString(header.state_root ?? header.stateRoot, 'header.state_root'));
  const authoritySetHash = normalizeHex(requireString(authoritySet.hash, 'authority_set.hash'));
  const computedAuthoritySetHash = grandpaAuthoritySetHash(Array.isArray(authoritySet.authorities) ? authoritySet.authorities : []);
  const targetHash = normalizeHex(requireString(justification.target_hash ?? justification.targetHash, 'justification.target_hash'));
  const targetNumber = Number(justification.target_number ?? justification.targetNumber);
  const setID = Number(authoritySet.set_id ?? authoritySet.setID);
  const justificationSetID = Number(justification.set_id ?? justification.setID);

  if (chain.chain_ref !== authoritySetChain.chain_ref) {
    return substrateFailure(chain, blockNumber, blockHash, storageProof, 'Substrate header chain does not match the GRANDPA authority set.');
  }
  if (setID !== justificationSetID) {
    return substrateFailure(chain, blockNumber, blockHash, storageProof, 'GRANDPA justification uses a different authority set.');
  }
  if (targetNumber !== blockNumber || targetHash !== blockHash) {
    return substrateFailure(chain, blockNumber, blockHash, storageProof, 'GRANDPA justification targets a different finalized header.');
  }
  if (authoritySetHash !== computedAuthoritySetHash) {
    return substrateFailure(chain, blockNumber, blockHash, storageProof, 'GRANDPA authority set hash is invalid.');
  }

  const conflictingJustification = payload.conflicting_justification ?? payload.conflictingJustification;
  if (conflictingJustification) {
    const conflictNumber = Number(conflictingJustification.target_number ?? conflictingJustification.targetNumber);
    const conflictHash = normalizeHex(requireString(conflictingJustification.target_hash ?? conflictingJustification.targetHash, 'conflicting_justification.target_hash'));
    if (conflictNumber === blockNumber
        && conflictHash !== targetHash
        && hasGrandpaTwoThirdsWeight(authoritySet.authorities, grandpaSignedAuthorities(conflictingJustification))) {
      return substrateFailure(chain, blockNumber, blockHash, storageProof, 'Conflicting GRANDPA justifications both reached the authority threshold.');
    }
  }

  if (!hasGrandpaTwoThirdsWeight(authoritySet.authorities, grandpaSignedAuthorities(justification))) {
    return substrateFailure(chain, blockNumber, blockHash, storageProof, 'GRANDPA justification did not reach the two-thirds authority threshold.');
  }

  if (storageProof) {
    const proofChain = resolveSubstrateChain(storageProof.chain_spec_id ?? storageProof.chain_ref ?? storageProof.chain ?? chain.chain_spec_id);
    const proofBlockHash = normalizeHex(requireString(storageProof.block_hash ?? storageProof.blockHash, 'storage_proof.block_hash'));
    if (proofChain.chain_ref !== chain.chain_ref || proofBlockHash !== blockHash) {
      return substrateFailure(chain, blockNumber, blockHash, storageProof, 'Substrate storage proof references a different chain or block.');
    }
    const computedRoot = computeSubstrateLocalMerkleRoot(
      requireString(storageProof.leaf_hash ?? storageProof.leafHash, 'storage_proof.leaf_hash'),
      Array.isArray(storageProof.witnesses) ? storageProof.witnesses : []
    );
    if (computedRoot !== stateRoot) {
      return substrateFailure(chain, blockNumber, blockHash, storageProof, 'Substrate storage proof did not resolve to the finalized state root.');
    }
  }

  return {
    verified: true,
    state: header.finalized === false ? 'proof_checked' : (chain.chain_ref === 'polkadot' ? 'synced' : 'proof_checked'),
    chain_ref: chain.chain_ref,
    chain_spec_id: chain.chain_spec_id,
    block_number: Number.isFinite(blockNumber) ? blockNumber : null,
    block_hash: blockHash,
    proof_id: storageProof ? String(storageProof.proof_id ?? storageProof.proofID ?? '') : null,
    storage_key: storageProof ? String(storageProof.storage_key ?? storageProof.storageKey ?? '') : null,
    summary: storageProof
      ? `Substrate storage proof checked against finalized header ${Number.isFinite(blockNumber) ? blockNumber : 'unknown'}.`
      : `GRANDPA finalized header ${Number.isFinite(blockNumber) ? blockNumber : 'unknown'} verified.`
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

function assertAvalancheFixture() {
  const computedValidatorSetHash = avalancheValidatorSetHash(avalancheFixtureValidators);
  if (computedValidatorSetHash !== avalancheFixtureValidatorSetHash) {
    throw new Error(`Avalanche validator fixture mismatch: ${computedValidatorSetHash}`);
  }
  const result = verifyAvalancheState({
    accepted_block: avalancheFixtureAcceptedBlock,
    validator_set: avalancheFixtureValidatorSet,
    finality_evidence: avalancheFixtureFinalityEvidence,
    evm_proof: avalancheFixtureEvmProofBundle
  });
  if (!result.verified) {
    throw new Error(`Avalanche state fixture mismatch: ${result.summary}`);
  }
}

function assertSolanaFixture() {
  const computedRoot = computeSolanaLocalMerkleRoot(solanaFixtureProof.leaf_hash, solanaFixtureProof.witnesses);
  if (computedRoot !== solanaFixtureSlotRoot.account_root) {
    throw new Error(`Solana fixture mismatch: ${computedRoot}`);
  }
}

function assertCosmosFixture() {
  const computedValidatorSetHash = tendermintValidatorSetHash(cosmosFixtureValidators);
  if (computedValidatorSetHash !== cosmosFixtureValidatorSetHash) {
    throw new Error(`Cosmos validator fixture mismatch: ${computedValidatorSetHash}`);
  }
  const result = verifyCosmosHeader({
    header: cosmosFixtureHeader,
    validator_set: cosmosFixtureValidatorSet,
    commit: cosmosFixtureCommit,
    trust_policy: cosmosFixtureTrustPolicy
  });
  if (!result.verified) {
    throw new Error(`Cosmos header fixture mismatch: ${result.summary}`);
  }
}

function assertSubstrateFixture() {
  const computedAuthoritySetHash = grandpaAuthoritySetHash(substrateFixtureAuthorities);
  if (computedAuthoritySetHash !== substrateFixtureAuthoritySetHash) {
    throw new Error(`Substrate authority fixture mismatch: ${computedAuthoritySetHash}`);
  }
  const result = verifySubstrateStorageProof({
    header: substrateFixtureHeader,
    authority_set: substrateFixtureAuthoritySet,
    justification: substrateFixtureJustification,
    storage_proof: substrateFixtureStorageProof
  });
  if (!result.verified) {
    throw new Error(`Substrate storage fixture mismatch: ${result.summary}`);
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

function avalancheFailure(network, blockNumber, blockHash, evmProof, summary) {
  return {
    verified: false,
    state: 'failed',
    chain_ref: network.chain_ref,
    block_number: Number.isFinite(blockNumber) ? blockNumber : null,
    block_hash: blockHash,
    proof_id: evmProof?.proof ? String(evmProof.proof.proof_id ?? evmProof.proof.proofID ?? '') : null,
    summary
  };
}

function solanaFailure(proofID, kind, chainRef, slot, rootSlot, summary) {
  return {
    verified: false,
    state: 'failed',
    proof_id: proofID,
    kind,
    chain_ref: chainRef,
    slot: Number.isFinite(slot) ? slot : null,
    root_slot: Number.isFinite(rootSlot) ? rootSlot : null,
    summary
  };
}

function cosmosFailure(chain, height, blockHash, validatorSetHash, summary) {
  return {
    verified: false,
    state: 'failed',
    chain_ref: chain.chain_ref,
    chain_id: chain.chain_id,
    height: Number.isFinite(height) ? height : null,
    block_hash: blockHash,
    validator_set_hash: validatorSetHash,
    summary
  };
}

function substrateFailure(chain, blockNumber, blockHash, storageProof, summary) {
  return {
    verified: false,
    state: 'failed',
    chain_ref: chain.chain_ref,
    chain_spec_id: chain.chain_spec_id,
    block_number: Number.isFinite(blockNumber) ? blockNumber : null,
    block_hash: blockHash,
    proof_id: storageProof ? String(storageProof.proof_id ?? storageProof.proofID ?? '') : null,
    storage_key: storageProof ? String(storageProof.storage_key ?? storageProof.storageKey ?? '') : null,
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

function resolveAvalancheNetwork(requestedNetwork) {
  if (!requestedNetwork) {
    return avalancheNetworks['avalanche-c'];
  }
  const normalized = String(requestedNetwork)
    .trim()
    .toLowerCase()
    .replace(/_/g, '-')
    .replace(/\s+/g, '-');
  if (avalancheNetworks[normalized]) {
    return avalancheNetworks[normalized];
  }
  if (normalized === 'avalanche' || normalized === 'avalanche-c-chain' || normalized === 'avax' || normalized === 'c-chain') {
    return avalancheNetworks['avalanche-c'];
  }
  const byID = Object.values(avalancheNetworks).find(network => String(network.chain_id) === normalized);
  return byID ?? avalancheNetworks['avalanche-c'];
}

function resolveSolanaCluster(requestedCluster) {
  if (!requestedCluster) {
    return solanaClusters['mainnet-beta'];
  }
  const normalized = String(requestedCluster)
    .trim()
    .toLowerCase()
    .replace(/_/g, '-')
    .replace(/\s+/g, '-');
  if (solanaClusters[normalized]) {
    return solanaClusters[normalized];
  }
  if (normalized === 'solana' || normalized === 'mainnet') {
    return solanaClusters['mainnet-beta'];
  }
  return solanaClusters['mainnet-beta'];
}

function resolveCosmosChain(requestedChain) {
  if (!requestedChain) {
    return cosmosChains['cosmoshub-4'];
  }
  const normalized = String(requestedChain)
    .trim()
    .toLowerCase()
    .replace(/_/g, '-')
    .replace(/\s+/g, '-');
  if (cosmosChains[normalized]) {
    return cosmosChains[normalized];
  }
  if (normalized === 'cosmos' || normalized === 'cosmoshub') {
    return cosmosChains['cosmoshub-4'];
  }
  return cosmosChains['cosmoshub-4'];
}

function resolveSubstrateChain(requestedChain) {
  if (!requestedChain) {
    return substrateChains.polkadot;
  }
  const normalized = String(requestedChain)
    .trim()
    .toLowerCase()
    .replace(/_/g, '-')
    .replace(/\s+/g, '-');
  if (substrateChains[normalized]) {
    return substrateChains[normalized];
  }
  if (normalized === 'dot' || normalized === 'polkadot-relay') {
    return substrateChains.polkadot;
  }
  return substrateChains.polkadot;
}

function evmFixtureLeafHash(kind, subject, key, value) {
  return sha256HexFromString([
    kind,
    String(subject).toLowerCase(),
    String(key ?? '').toLowerCase(),
    String(value).toLowerCase()
  ].join('|'));
}

function avalancheValidatorSetHash(validators) {
  const payload = validators
    .map(validator => `${normalizeID(requireString(validator.node_id ?? validator.nodeID, 'validator.node_id'))}:${Number(validator.weight)}`)
    .sort()
    .join('|');
  return sha256HexFromString(payload);
}

function avalancheSignedValidators(finalityEvidence) {
  return new Set((Array.isArray(finalityEvidence.signatures) ? finalityEvidence.signatures : [])
    .filter(signature => signature.signed !== false)
    .map(signature => normalizeID(requireString(signature.node_id ?? signature.nodeID, 'signature.node_id'))));
}

function hasAvalancheAcceptedQuorum(validators, validatorIDs) {
  let totalWeight = 0;
  let signedWeight = 0;
  for (const validator of Array.isArray(validators) ? validators : []) {
    const weight = Number(validator.weight);
    if (!Number.isFinite(weight) || weight < 0) {
      continue;
    }
    totalWeight += weight;
    const nodeID = normalizeID(requireString(validator.node_id ?? validator.nodeID, 'validator.node_id'));
    if (validatorIDs.has(nodeID)) {
      signedWeight += weight;
    }
  }
  return totalWeight > 0 && signedWeight * 5 >= totalWeight * 4;
}

function solanaFixtureLeafHash(kind, subject, value) {
  return sha256HexFromString([
    kind,
    String(subject).toLowerCase(),
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

function computeSolanaLocalMerkleRoot(leafHash, witnesses) {
  let node = Buffer.from(normalizeHex(leafHash), 'hex');
  for (const witness of witnesses) {
    const siblingHash = Buffer.from(normalizeHex(requireString(witness.hash, 'witness.hash')), 'hex');
    const position = requireString(witness.position, 'witness.position');
    if (position !== 'left' && position !== 'right') {
      throw Object.assign(new Error(`unsupported Solana witness position: ${position}`), { statusCode: 400 });
    }
    node = position === 'left'
      ? crypto.createHash('sha256').update(Buffer.concat([siblingHash, node])).digest()
      : crypto.createHash('sha256').update(Buffer.concat([node, siblingHash])).digest();
  }
  return node.toString('hex');
}

function tendermintValidatorSetHash(validators) {
  const payload = validators
    .map(validator => `${normalizeHex(requireString(validator.address, 'validator.address'))}:${Number(validator.voting_power ?? validator.votingPower)}`)
    .sort()
    .join('|');
  return sha256HexFromString(payload);
}

function tendermintHeaderHash(header) {
  const chain = resolveCosmosChain(header.chain_id ?? header.chain_ref ?? header.chain);
  return sha256HexFromString([
    chain.chain_id,
    String(Number(header.height)),
    String(Number(header.time_unix_seconds ?? header.timeUnixSeconds)),
    normalizeHex(requireString(header.last_block_id_hash ?? header.lastBlockIDHash, 'header.last_block_id_hash')),
    normalizeHex(requireString(header.validators_hash ?? header.validatorsHash, 'header.validators_hash')),
    normalizeHex(requireString(header.next_validators_hash ?? header.nextValidatorsHash, 'header.next_validators_hash')),
    normalizeHex(requireString(header.app_hash ?? header.appHash, 'header.app_hash')),
    header.data_hash ?? header.dataHash ? normalizeHex(header.data_hash ?? header.dataHash) : '',
    header.evidence_hash ?? header.evidenceHash ? normalizeHex(header.evidence_hash ?? header.evidenceHash) : '',
    normalizeHex(requireString(header.proposer_address ?? header.proposerAddress, 'header.proposer_address'))
  ].join('|'));
}

function signedAddresses(commit) {
  return new Set((Array.isArray(commit.signatures) ? commit.signatures : [])
    .filter(signature => signature.signed !== false)
    .map(signature => normalizeHex(requireString(signature.validator_address ?? signature.validatorAddress, 'signature.validator_address'))));
}

function hasTendermintTwoThirdsPower(validators, addresses) {
  let totalPower = 0;
  let signedPower = 0;
  for (const validator of Array.isArray(validators) ? validators : []) {
    const power = Number(validator.voting_power ?? validator.votingPower);
    if (!Number.isFinite(power) || power < 0) {
      continue;
    }
    totalPower += power;
    const address = normalizeHex(requireString(validator.address, 'validator.address'));
    if (addresses.has(address)) {
      signedPower += power;
    }
  }
  return signedPower * 3 > totalPower * 2;
}

function grandpaAuthoritySetHash(authorities) {
  const payload = authorities
    .map(authority => `${normalizeHex(requireString(authority.authority_id ?? authority.authorityID, 'authority.authority_id'))}:${Number(authority.weight)}`)
    .sort()
    .join('|');
  return sha256HexFromString(payload);
}

function grandpaSignedAuthorities(justification) {
  return new Set((Array.isArray(justification.signatures) ? justification.signatures : [])
    .filter(signature => signature.signed !== false)
    .map(signature => normalizeHex(requireString(signature.authority_id ?? signature.authorityID, 'signature.authority_id'))));
}

function hasGrandpaTwoThirdsWeight(authorities, authorityIDs) {
  let totalWeight = 0;
  let signedWeight = 0;
  for (const authority of Array.isArray(authorities) ? authorities : []) {
    const weight = Number(authority.weight);
    if (!Number.isFinite(weight) || weight < 0) {
      continue;
    }
    totalWeight += weight;
    const authorityID = normalizeHex(requireString(authority.authority_id ?? authority.authorityID, 'authority.authority_id'));
    if (authorityIDs.has(authorityID)) {
      signedWeight += weight;
    }
  }
  return signedWeight * 3 > totalWeight * 2;
}

function substrateFixtureStorageLeafHash(storageKey, valueHash) {
  return sha256HexFromString([
    String(storageKey).toLowerCase(),
    normalizeHex(valueHash)
  ].join('|'));
}

function computeSubstrateLocalMerkleRoot(leafHash, witnesses) {
  let node = Buffer.from(normalizeHex(leafHash), 'hex');
  for (const witness of witnesses) {
    const siblingHash = Buffer.from(normalizeHex(requireString(witness.hash, 'witness.hash')), 'hex');
    const position = requireString(witness.position, 'witness.position');
    if (position !== 'left' && position !== 'right') {
      throw Object.assign(new Error(`unsupported Substrate witness position: ${position}`), { statusCode: 400 });
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

function normalizeID(value) {
  return String(value).trim().toLowerCase();
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
