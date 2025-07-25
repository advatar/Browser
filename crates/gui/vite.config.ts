import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  root: './src',
  publicDir: '../public',
  build: {
    outDir: '../dist',
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'src/index.html'),
      },
    },
  },
  resolve: {
    alias: [
      {
        find: '@',
        replacement: resolve(__dirname, 'src'),
      },
    ],
    extensions: ['.js', '.jsx', '.ts', '.tsx', '.json'],
  },
  server: {
    port: 3000,
    strictPort: true,
  },
  // Enable TypeScript checking during development
  plugins: [],
  optimizeDeps: {
    esbuildOptions: {
      loader: {
        '.ts': 'ts',
      },
    },
  },
  esbuild: {
    include: /.*\.tsx?$/,
    exclude: [],
    loader: 'ts',
  },
});
