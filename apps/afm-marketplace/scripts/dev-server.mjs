import { selfTest, startMarketplaceServer } from '../src/main.mjs';

const args = new Set(process.argv.slice(2));

if (args.has('--self-test')) {
  const result = await selfTest();
  console.log('[marketplace] self-test complete', JSON.stringify(result));
  process.exit(0);
}

if (args.has('--snapshot')) {
  console.log('[marketplace] snapshot ready');
  process.exit(0);
}

const { url } = await startMarketplaceServer();
console.log(`[marketplace] listening on ${url}`);
