#!/usr/bin/env node
// serve-dashboard.js — zero-dependency Node.js server for claude-baton dashboard
// Usage: node .baton/serve-dashboard.js
// Or:    PORT=8080 node .baton/serve-dashboard.js

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.env.PORT, 10) || 3456;
const BATON_DIR = path.resolve(__dirname);

const MIME = {
  '.html': 'text/html', '.css': 'text/css', '.js': 'application/javascript',
  '.json': 'application/json', '.md': 'text/plain', '.png': 'image/png',
  '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
};

const API_FILES = {
  '/api/state':      { file: 'state.json',          type: 'application/json' },
  '/api/todo':       { file: 'todo.md',              type: 'text/plain; charset=utf-8' },
  '/api/lessons':    { file: 'lessons.md',           type: 'text/plain; charset=utf-8' },
  '/api/complexity': { file: 'complexity-score.md',  type: 'text/plain; charset=utf-8' },
};

const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, OPTIONS' };

function sendJSON(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { ...CORS, 'Content-Type': 'application/json' });
  res.end(body);
}

const server = http.createServer((req, res) => {
  if (req.method === 'OPTIONS') { res.writeHead(204, CORS); return res.end(); }
  if (req.method !== 'GET') return sendJSON(res, 405, { error: 'method not allowed' });

  const url = req.url.split('?')[0];

  // API endpoints
  const api = API_FILES[url];
  if (api) {
    const fp = path.join(BATON_DIR, api.file);
    if (!fs.existsSync(fp)) return sendJSON(res, 404, { error: 'file not found' });
    const content = fs.readFileSync(fp, 'utf-8');
    res.writeHead(200, { ...CORS, 'Content-Type': api.type });
    return res.end(content);
  }

  // Serve dashboard.html at root
  const filePath = url === '/' ? path.join(BATON_DIR, 'dashboard.html')
                               : path.join(BATON_DIR, url.replace(/^\//, ''));

  // Prevent directory traversal
  if (!filePath.startsWith(BATON_DIR)) return sendJSON(res, 403, { error: 'forbidden' });

  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory())
    return sendJSON(res, 404, { error: 'not found' });

  const ext = path.extname(filePath);
  const ct = MIME[ext] || 'application/octet-stream';
  res.writeHead(200, { ...CORS, 'Content-Type': ct });
  fs.createReadStream(filePath).pipe(res);
});

server.listen(PORT, () => {
  console.log(`\n  \u{1F3AF} claude-baton dashboard running at http://localhost:${PORT}\n`);
});
