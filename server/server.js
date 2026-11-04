// Tiny "remote database" for the offline-first task app.
// No dependencies: run with `node server.js`. Data lives in data.json.
//
//   GET  /health              -> { ok: true }
//   GET  /tasks?since=<seq>   -> { seq, tasks: [ ...tasks changed after seq ] }
//   PUT  /tasks/:id           -> create/update one task (optimistic concurrency)
//   POST /reset               -> wipe all data (handy before a demo)
//
// Every task has a `version` (bumped on each accepted write) and a `seq`
// (global change counter, lets clients ask "what changed since I last looked").
// A PUT must carry `baseVersion` (the version the client last saw). If it does
// not match the stored version, someone else changed the task first and the
// server answers 409 with its copy so the client can merge.
// `opId` makes retries idempotent: replaying the same operation is a no-op.

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;
const FILE = path.join(__dirname, 'data.json');

let db = { seq: 0, tasks: {} };
try {
  db = JSON.parse(fs.readFileSync(FILE, 'utf8'));
} catch (_) {
  /* first run */
}

function save() {
  const tmp = FILE + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(db));
  fs.renameSync(tmp, FILE); // atomic replace: a crash never leaves a half-written file
}

function send(res, code, body) {
  res.writeHead(code, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (c) => {
      data += c;
      if (data.length > 1e6) reject(new Error('body too large'));
    });
    req.on('end', () => {
      try {
        resolve(JSON.parse(data || '{}'));
      } catch (e) {
        reject(e);
      }
    });
  });
}

function publicTask(t) {
  const { lastOpId, ...rest } = t;
  return rest;
}

function pick(body) {
  return {
    title: String(body.title),
    notes: String(body.notes ?? ''),
    completed: !!body.completed,
    priority: Number.isInteger(body.priority) ? body.priority : 1,
    dueAt: Number.isFinite(body.dueAt) ? body.dueAt : null,
    category: String(body.category ?? ''),
    deleted: !!body.deleted,
    repeat: Number.isInteger(body.repeat) ? body.repeat : 0,
    position: Number.isFinite(body.position) ? body.position : null,
    updatedAt: Number.isFinite(body.updatedAt) ? body.updatedAt : Date.now(),
  };
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  try {
    if (req.method === 'GET' && url.pathname === '/health') {
      return send(res, 200, { ok: true });
    }

    if (req.method === 'GET' && url.pathname === '/tasks') {
      const since = Number(url.searchParams.get('since') || 0);
      const tasks = Object.values(db.tasks)
        .filter((t) => t.seq > since)
        .sort((a, b) => a.seq - b.seq)
        .map(publicTask);
      return send(res, 200, { seq: db.seq, tasks });
    }

    const m = url.pathname.match(/^\/tasks\/([\w-]+)$/);
    if (req.method === 'PUT' && m) {
      const id = m[1];
      const body = await readBody(req);
      if (typeof body.title !== 'string' || !body.title.trim()) {
        return send(res, 400, { error: 'title is required' });
      }
      const cur = db.tasks[id];

      if (cur && body.opId && cur.lastOpId === body.opId) {
        return send(res, 200, { task: publicTask(cur) }); // retry of an op we already applied
      }
      if (cur && body.baseVersion !== cur.version) {
        return send(res, 409, { task: publicTask(cur) });
      }

      const next = {
        id,
        ...pick(body),
        version: (cur ? cur.version : 0) + 1,
        seq: ++db.seq,
        lastOpId: body.opId || null,
      };
      db.tasks[id] = next;
      save();
      return send(res, cur ? 200 : 201, { task: publicTask(next) });
    }

    if (req.method === 'POST' && url.pathname === '/reset') {
      db = { seq: 0, tasks: {} };
      save();
      return send(res, 200, { ok: true });
    }

    send(res, 404, { error: 'not found' });
  } catch (e) {
    send(res, 400, { error: String(e.message || e) });
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Task server listening on http://0.0.0.0:${PORT}`);
});
