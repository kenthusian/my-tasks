// Smoke test for the sync server. Run: node test_server.js
// Starts the server on a spare port with a scratch data file, checks the
// create / idempotent-retry / conflict / pull behaviour, then exits.
const { spawn } = require('child_process');
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const PORT = 3999;
const base = `http://127.0.0.1:${PORT}`;
const data = path.join(__dirname, 'data.json');
const backup = fs.existsSync(data) ? fs.readFileSync(data) : null;
fs.rmSync(data, { force: true });

const put = (id, body) =>
  fetch(`${base}/tasks/${id}`, {
    method: 'PUT',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  }).then(async (r) => ({ status: r.status, body: await r.json() }));

(async () => {
  const srv = spawn('node', ['server.js'], { cwd: __dirname, env: { ...process.env, PORT } });
  await new Promise((r) => setTimeout(r, 600));
  try {
    let r = await put('t1', { title: 'A', baseVersion: 0, opId: 'op1' });
    assert.strictEqual(r.status, 201);
    assert.strictEqual(r.body.task.version, 1);

    r = await put('t1', { title: 'A', baseVersion: 0, opId: 'op1' }); // lost-reply retry
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.body.task.version, 1, 'retry must not bump version');

    r = await put('t1', { title: 'B', baseVersion: 1, opId: 'op2' });
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.body.task.version, 2);

    r = await put('t1', { title: 'C', baseVersion: 1, opId: 'op3' }); // stale base
    assert.strictEqual(r.status, 409);
    assert.strictEqual(r.body.task.title, 'B');

    r = await put('t1', { title: '  ', baseVersion: 2, opId: 'op4' });
    assert.strictEqual(r.status, 400);

    let list = await (await fetch(`${base}/tasks?since=0`)).json();
    assert.strictEqual(list.tasks.length, 1, 'no duplicates');
    list = await (await fetch(`${base}/tasks?since=${list.seq}`)).json();
    assert.strictEqual(list.tasks.length, 0);

    console.log('server tests passed');
  } finally {
    srv.kill();
    await new Promise((r) => setTimeout(r, 200));
    if (backup) fs.writeFileSync(data, backup);
    else fs.rmSync(data, { force: true });
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
