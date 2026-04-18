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
  if (CACHEABLE_ASSET.test(url.pathname)) {
    event.respondWith(
      caches.open(ASSET_CACHE).then((cache) => {
        return cache.match(event.request).then((cached) => {
          if (cached) return cached;
          return fetch(event.request).then((response) => {
            if (response.ok) cache.put(event.request, response.clone());
            return response;
          }).catch(() => new Response('', { status: 503 }));
        });
      })
    );
    return;
  }

  // Code (HTML, JS, CSS, JSON): Network-First
  // Try network, fall back to cache for offline support
  if (/\.(js|css|html|json)$/.test(url.pathname) || url.pathname === '/') {
    event.respondWith(
      fetch(event.request).then((response) => {
        return response;
      }).catch(() => {
        // Network failed — serve from cache if available
        return caches.match(event.request).then((cached) => {
          return cached || new Response('', { status: 503 });
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
