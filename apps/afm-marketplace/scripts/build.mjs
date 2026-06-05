import { selfTest } from '../src/main.mjs';

const result = await selfTest();
console.log('[marketplace] build smoke passed', JSON.stringify(result));
