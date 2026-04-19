// BridgeRead Cache Service Worker
// - Assets (audio, images, fonts): Cache forever (never change)
// - Code (HTML, JS, CSS): Network-First (always get latest)
// - Version check: force reload all clients when version.json changes

const ASSET_CACHE = 'bridgeread-assets-v2';

// File types to cache permanently (these never change)
const CACHEABLE_ASSET = /\.(mp3|wav|ogg|webp|png|jpg|jpeg|gif|woff2|woff|ttf)$/i;

// Install: activate immediately
self.addEventListener('install', (event) => {
  self.skipWaiting();
});

// Activate: clean old caches, take control
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) => {
      return Promise.all(
        names.filter((name) => name !== ASSET_CACHE)
             .map((name) => caches.delete(name))
      );
    }).then(() => self.clients.claim())
  );
});

// Fetch handler
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  if (event.request.method !== 'GET') return;
  if (url.origin !== self.location.origin) return;

  // Assets (audio/image/font): Cache-First, never expire
  // But validate: don't cache truncated files (< 2KB for audio — phonemes
  // can be 5-10KB legit, only HTML 404 pages or truly broken responses are
  // typically < 2KB)
  if (CACHEABLE_ASSET.test(url.pathname)) {
    event.respondWith(
      caches.open(ASSET_CACHE).then((cache) => {
        return cache.match(event.request).then((cached) => {
          if (cached) {
            var contentLength = cached.headers.get('content-length');
            if (contentLength && parseInt(contentLength) < 2000 && /\.(mp3|wav)$/i.test(url.pathname)) {
              console.warn('[SW] Cached audio too small, re-fetching:', url.pathname);
              // Refetch without Range headers so we get full 200, not 206
              // (Cache API rejects 206 Partial Content responses)
              return fetch(url.pathname).then((response) => {
                if (response.status === 200) cache.put(event.request, response.clone());
                return response;
              }).catch(() => cached);
            }
            return cached;
          }
          return fetch(event.request).then((response) => {
            // Only cache full 200 responses — 206 Partial Content (range
            // requests for audio) cannot be stored in Cache API.
            if (response.status === 200) cache.put(event.request, response.clone());
            return response;
          }).catch(() => new Response('', { status: 503 }));
        });
      })
    );
    return;
  }

  // Code (HTML, JS, CSS, JSON): Network-First with timeout + cache backup
  if (/\.(js|css|html|json)$/.test(url.pathname) || url.pathname === '/') {
    var CODE_CACHE = 'bridgeread-code-v1';
    event.respondWith(
      caches.open(CODE_CACHE).then((cache) => {
        // Race: network with 5s timeout vs cache
        var networkFetch = fetch(event.request).then((response) => {
          if (response.ok) {
            cache.put(event.request, response.clone()); // cache for next time
          }
          return response;
        });

        var timeout = new Promise((_, reject) => {
          setTimeout(() => reject(new Error('timeout')), 5000);
        });

        return Promise.race([networkFetch, timeout]).catch(() => {
          // Network failed or timed out — serve from cache
          return cache.match(event.request).then((cached) => {
            return cached || new Response('', { status: 503 });
          });
        });
      })
    );
    return;
  }
});

// Listen for version check messages from the main page
self.addEventListener('message', (event) => {
  if (event.data === 'CHECK_VERSION') {
    // Fetch version.json from network (bypass cache)
    fetch('/version.json?t=' + Date.now())
      .then(res => res.json())
      .then(data => {
        // Notify all clients of the current server version
        self.clients.matchAll().then(clients => {
          clients.forEach(client => {
            client.postMessage({ type: 'VERSION', version: data.version });
          });
        });
      })
      .catch(() => {});
  }
});
