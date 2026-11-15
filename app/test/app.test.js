'use strict';

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { createApp } = require('../src/app');
const { createStore } = require('../src/store');

let server;
let base;

before(async () => {
  const summary = path.join(os.tmpdir(), `scan-summary-${process.pid}.json`);
  fs.writeFileSync(summary, JSON.stringify({ trivy: { CRITICAL: 0 } }));
  process.env.SCAN_SUMMARY_PATH = summary;
  server = createApp({ store: createStore([]) }).listen(0);
  await new Promise((r) => server.once('listening', r));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

test('health endpoints respond', async () => {
  for (const p of ['/healthz', '/readyz']) {
    const res = await fetch(base + p);
    assert.equal(res.status, 200);
  }
});

test('security headers are set', async () => {
  const res = await fetch(base + '/');
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-security-policy'), /default-src 'self'/);
  assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(res.headers.get('x-frame-options'), 'SAMEORIGIN');
  assert.equal(res.headers.get('x-powered-by'), null);
});

test('info exposes build metadata', async () => {
  const body = await (await fetch(base + '/api/info')).json();
  assert.equal(body.app, 'ShipGuard');
  assert.ok(body.version);
});

test('scan summary is read from mounted file', async () => {
  const body = await (await fetch(base + '/api/scans')).json();
  assert.equal(body.trivy.CRITICAL, 0);
});

test('release CRUD with validation', async () => {
  const bad = await fetch(base + '/api/releases', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ title: '' }),
  });
  assert.equal(bad.status, 400);

  const badSev = await fetch(base + '/api/releases', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ title: 'x', severity: 'nuclear' }),
  });
  assert.equal(badSev.status, 400);

  const created = await fetch(base + '/api/releases', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ title: 'Patched CVE-2026-0001', severity: 'high' }),
  });
  assert.equal(created.status, 201);
  const item = await created.json();

  const list = await (await fetch(base + '/api/releases')).json();
  assert.equal(list.length, 1);

  assert.equal((await fetch(`${base}/api/releases/${item.id}`, { method: 'DELETE' })).status, 204);
  assert.equal((await fetch(`${base}/api/releases/${item.id}`, { method: 'DELETE' })).status, 404);
});

test('unknown routes return 404', async () => {
  assert.equal((await fetch(base + '/api/nope')).status, 404);
  assert.equal((await fetch(base + '/nope')).status, 404);
});

test('store trims and caps titles', () => {
  const s = createStore([]);
  assert.equal(s.add({ title: '  hi  ' }).item.title, 'hi');
  assert.ok(s.add({ title: 'x'.repeat(121) }).error);
});
