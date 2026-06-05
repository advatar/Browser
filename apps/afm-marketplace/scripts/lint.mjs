import { readFile } from 'node:fs/promises';

const files = [
  new URL('../src/main.mjs', import.meta.url),
  new URL('../src/main.test.mjs', import.meta.url),
  new URL('./dev-server.mjs', import.meta.url),
  new URL('./build.mjs', import.meta.url)
];

for (const file of files) {
  const source = await readFile(file, 'utf8');
  if (source.includes('placeholder')) {
    throw new Error(`${file.pathname} still contains placeholder text`);
  }
}

console.log('[marketplace] lint passed');
