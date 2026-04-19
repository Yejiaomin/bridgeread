// Local dev server: serves build/web + proxies /api to a backend.
// Defaults to production (mybridgeread.com over https). Override with env
// vars to point at a local backend, e.g. for offline US dev:
//
//   API_HOST=localhost API_PORT=3000 API_PROTOCOL=http node local-server.js
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const PORT = 8080;
const WEBROOT = path.join(__dirname, 'build', 'web');
const API_HOST = process.env.API_HOST || 'mybridgeread.com';
const API_PORT = parseInt(process.env.API_PORT || (process.env.API_PROTOCOL === 'http' ? '80' : '443'), 10);
const API_PROTOCOL = process.env.API_PROTOCOL || 'https';
const apiClient = API_PROTOCOL === 'http' ? http : https;

const MIME = {
  '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css',
  '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.webp': 'image/webp', '.mp3': 'audio/mpeg', '.wav': 'audio/wav',
  '.woff2': 'font/woff2', '.wasm': 'application/wasm',
};

http.createServer((req, res) => {
  // Proxy /api requests to production server
  if (req.url.startsWith('/api/')) {
    let body = [];
    req.on('data', chunk => body.push(chunk));
    req.on('end', () => {
      const opts = {
        hostname: API_HOST, port: API_PORT, path: req.url,
        method: req.method,
        headers: { ...req.headers, host: API_HOST },
      };
      const proxy = apiClient.request(opts, (pRes) => {
        res.writeHead(pRes.statusCode, pRes.headers);
        pRes.pipe(res);
      });
      proxy.on('error', (e) => {
        res.writeHead(502);
        res.end('Proxy error: ' + e.message);
      });
      if (body.length) proxy.write(Buffer.concat(body));
      proxy.end();
    });
    return;
  }

  // Serve static files
  let filePath = path.join(WEBROOT, req.url === '/' ? 'index.html' : req.url);
  // SPA fallback
  if (!fs.existsSync(filePath)) filePath = path.join(WEBROOT, 'index.html');

  const ext = path.extname(filePath);
  const mime = MIME[ext] || 'application/octet-stream';
  try {
    const data = fs.readFileSync(filePath);
    res.writeHead(200, { 'Content-Type': mime });
    res.end(data);
  } catch (e) {
    res.writeHead(404);
    res.end('Not found');
  }
}).listen(PORT, () => {
  console.log(`Local dev server: http://localhost:${PORT}`);
  console.log(`API proxy -> ${API_PROTOCOL}://${API_HOST}:${API_PORT}`);
});
