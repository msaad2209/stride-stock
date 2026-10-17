import { execFileSync } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

function versionFiles(): Plugin {
  let appVersion = 'local';
  return {
    name: 'stridestock-version-files',
    config() {
      try {
        appVersion = execFileSync('git', ['rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim();
      } catch {
        appVersion = process.env.VITE_APP_VERSION || 'local';
      }
      return { define: { 'import.meta.env.VITE_APP_VERSION': JSON.stringify(appVersion) } };
    },
    async closeBundle() {
      const dist = resolve(process.cwd(), 'dist');
      await mkdir(dist, { recursive: true });
      await writeFile(resolve(dist, 'version.json'), JSON.stringify({ commit: appVersion, builtAt: new Date().toISOString() }));
    },
  };
}

export default defineConfig({
  resolve: { preserveSymlinks: true },
  optimizeDeps: { entries: ['index.html'] },
  plugins: [
    react(),
    versionFiles(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icon.svg'],
      manifest: {
        name: 'StrideStock', short_name: 'StrideStock', description: 'Footwear shop stock and sales',
        theme_color: '#173f35', background_color: '#f5f6f2', display: 'standalone', start_url: '/',
        icons: [{ src: '/icon.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'any maskable' }],
      },
      workbox: {
        skipWaiting: true,
        clientsClaim: true,
        cleanupOutdatedCaches: true,
        globIgnores: ['**/index.html', '**/version.json'],
        navigateFallback: '/index.html',
        runtimeCaching: [
          { urlPattern: ({ url }) => url.hostname.endsWith('.supabase.co'), handler: 'NetworkOnly' },
          { urlPattern: ({ url }) => url.pathname === '/version.json', handler: 'NetworkOnly' },
          { urlPattern: ({ request }) => request.mode === 'navigate', handler: 'NetworkFirst', options: { cacheName: 'stride-documents', networkTimeoutSeconds: 3 } },
        ],
      },
    }),
  ],
  test: { environment: 'node' },
});
