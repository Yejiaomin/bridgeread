// BridgeRead Cache Service Worker
// Cache-First strategy for audio, images, and fonts
// Network-First for HTML/JS (always get latest code)

const CACHE_NAME = 'bridgeread-assets-v1';

// File types to cache (audio, images, fonts)
const CACHEABLE = /\.(mp3|wav|ogg|webp|png|jpg|jpeg|gif|woff2|woff|ttf)$/i;

// Install: just activate immediately
self.addEventListener('install', (event) => {
  self.skipWaiting();
});

// Activate: clean old caches, take control
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) => {
      return Promise.all(
        names.filter((name) => name !== CACHE_NAME)
             .map((name) => caches.delete(name))
      );
    }).then(() => self.clients.claim())
  );
});

// Fetch: Cache-First for assets, Network-First for everything else
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Only handle same-origin GET requests
  if (event.request.method !== 'GET') return;
  if (url.origin !== self.location.origin) return;

  // Cache-First for audio/image/font assets
  if (CACHEABLE.test(url.pathname)) {
    event.respondWith(
      caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((cached) => {
          if (cached) return cached; // Cache hit — instant!

          // Cache miss — fetch, cache, return
          return fetch(event.request).then((response) => {
            if (response.ok) {
              cache.put(event.request, response.clone());
            }
            return response;
          }).catch(() => {
            // Network failed, no cache — return empty response
            return new Response('', { status: 503 });
          });
        });
      })
    );
    return;
  }

  // Everything else (HTML, JS, JSON): Network-First
  // Don't cache — always get latest code
});
