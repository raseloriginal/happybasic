import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootEnvPath = path.resolve(__dirname, '../../../.env');

function loadEnv(filePath) {
  if (!fs.existsSync(filePath)) return;
  for (const raw of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#') || !line.includes('=')) continue;
    const idx = line.indexOf('=');
    const key = line.slice(0, idx).trim();
    let val = line.slice(idx + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = val;
  }
}

loadEnv(rootEnvPath);

const PORT = Number(process.env.SERVICE_NODE_PORT || 3001);
const SERVICE_TOKEN = process.env.INTERNAL_SERVICE_TOKEN || '';

function sendJson(res, status, payload) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=UTF-8' });
  res.end(JSON.stringify(payload));
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

  if (SERVICE_TOKEN && req.headers['x-service-token'] !== SERVICE_TOKEN) {
    return sendJson(res, 401, { error: 'Unauthorized service token' });
  }

  if (req.method === 'GET' && url.pathname === '/health') {
    return sendJson(res, 200, {
      status: 'ok',
      service: 'node',
      runtime: process.version,
    });
  }

  return sendJson(res, 404, { error: 'Not Found' });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[node] listening on http://127.0.0.1:${PORT}`);
});
